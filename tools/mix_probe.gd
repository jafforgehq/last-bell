extends SceneTree
## Measures what the mix really does, in the engine, with no ear: the game's own sound nodes play on the real buses (on a real generated town, with Ruth and the dead as the rules have them), a
## capture effect on the Master bus, after its limiter, records what would reach the speakers, and the recording is measured: the peak (dBFS) and the loudest 400 ms momentary loudness (K-weighted,
## both channels, LUFS: the same standard as tools/audio_measure.py, but at the master and in stereo: a mono file played in the middle is 3 LU louder here than in the python table).
## One Godot at a time, headless (the dummy audio driver mixes in real time; about two minutes for everything):
##
##   Godot --headless --path . --script res://tools/mix_probe.gd -- --out=/tmp/mix.txt [--only=gun,steps]
##
## Scenarios (`--only=` takes some): grounds gun melee reload steps dead voices ruth weather rain beds music ui duck idle crowd
## Each prints "name   peak dBFS   M-max LUFS" and sometimes a note. The numbers are the ones in docs/audio-mix.md. Nothing in the game loads this file.

const Helpers := preload("res://tests/helpers.gd")
const SoundNode := preload("res://scripts/audio/sound.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Foley := preload("res://scripts/audio/foley.gd")

var cap: AudioEffectCapture
var rate := 44100.0
var lines: Array = []
var _out_path := ""
var _only: Array = []
var sim
var world
var game
var sound
var me
var sc


class Game:
	extends Node
	var sim
	var world
	var data := {}
	var speed := 1
	var title_mode := false
	var menu_open := false
	var cam_center := Vector2.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_path = a.substr(6)
		if a.begins_with("--only="):
			_only = a.substr(7).split(",")
	rate = AudioServer.get_mix_rate()
	Buses.apply_all()
	var master := AudioServer.get_bus_index("Master")
	cap = AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(master, cap)
	await process_frame
	await _boot()
	await _run()
	var text := "\n".join(lines) + "\n"
	print(text)
	if _out_path != "":
		var f := FileAccess.open(_out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
	quit()


func _boot() -> void:
	var tg: Dictionary = Helpers.town_game(3, {"blocks": 2})
	sim = tg.sim
	world = tg.world
	game = Game.new()
	game.sim = sim
	game.world = world
	root.add_child(game)
	me = sim.avatar.player()
	game.cam_center = Vector2(me.x, me.y)
	var f := FileAccess.open("res://assets/data/map.json", FileAccess.READ)
	var map = JSON.parse_string(f.get_as_text())
	# a camera, as the game has one: the positional voices hear from where it is (without one the listener is the middle of the window and a sound put at the origin is far from it)
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	sound = SoundNode.new()
	root.add_child(sound)
	sound.setup(map.get("sounds", {}))
	sound.attach(game)
	sc = sound.scape
	await process_frame
	lines.append("(town seed 3: %d x %d tiles, Ruth at %.1f, %.1f; mix rate %d Hz)" % [int(world.W), int(world.H), me.x, me.y, int(rate)])


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _run() -> void:
	if _want("grounds"):
		_grounds()
	if _want("gun"):
		await _gun()
	if _want("melee"):
		await _melee()
	if _want("reload"):
		await _reload()
	if _want("steps"):
		await _steps()
	if _want("dead"):
		await _dead()
	if _want("voices"):
		await _voices()
	if _want("ruth"):
		await _ruth()
	if _want("weather"):
		await _weather()
	if _want("rain"):
		await _rain()
	if _want("beds"):
		await _beds()
	if _want("music"):
		await _music()
	if _want("ui"):
		await _ui()
	if _want("duck"):
		await _duck()
	if _want("idle"):
		await _idle()
	if _want("crowd"):
		await _crowd()


# ------------------------------------------------------------------------------------------ the scenarios --

## How many tiles of the town are each ground (the lookup, over every tile).
func _grounds() -> void:
	var counts := {}
	var t0 := Time.get_ticks_usec()
	for y in int(world.H):
		for x in int(world.W):
			var g := Foley.ground_at(world, x + 0.5, y + 0.5)
			counts[g] = int(counts.get(g, 0)) + 1
	var us := float(Time.get_ticks_usec() - t0) / float(int(world.W) * int(world.H))
	lines.append("GROUNDS (every tile of the town): %s  (%.2f microseconds a lookup, with the loop)" % [str(counts), us])


func _gun() -> void:
	lines.append("-- gun")
	var at := Vector2(me.x, me.y)
	var listener := at
	# the old shot as the game played it (combat_fx: 0.8 x 0.9..1.0 by distance)
	await _one("old shot_shotgun (level 0.76)", func(): sound.play("shot_shotgun", 0.76, 0.0), 1.6)
	# the new one in the open and in a room (the room's answer is the rules'; here by hand)
	for room in [false, true]:
		var name := "blast_in" if room else "blast_out"
		var full: Array = Foley.load_group("gun:in" if room else "gun:out")
		for i in full.size():
			var idx := i
			await _one("%s_%d at gain %.1f dB" % [name, idx, float(Foley.LEVEL_DB["gun_in" if room else "gun_out"])], func():
				sound.streams[name] = [full[idx]]
				sound.play(name, db_to_linear(float(Foley.LEVEL_DB["gun_in" if room else "gun_out"])), 0.0), 1.6)
		sound.streams[name] = full
	lines.append("(listener and shooter in the same place: %s)" % str(at == listener))


func _melee() -> void:
	lines.append("-- melee (as combat_fx plays them: level by distance 1, a hair of pitch)")
	await _one("melee_swing -> swoosh", func(): sound.play("melee_swing", 1.0, 0.0), 1.0)
	await _one("melee_hit -> thud", func(): sound.play("melee_hit", 0.95, 0.0), 1.0)
	await _one("melee_kill (wet, 0.8)", func(): sound.play("melee_kill", 0.8, 0.0), 1.0)
	await _one("thud + kill together (a killing blow)", func():
		sound.play("melee_hit", 0.95, 0.0)
		sound.play("melee_kill", 0.8, 0.0), 1.0)


func _reload() -> void:
	lines.append("-- reload and trigger")
	await _one("shell_in -> shell_load (0.85)", func(): sound.play("shell_in", 0.85, 0.0), 0.8)
	await _one("pump -> pump_rack (0.9)", func(): sound.play("pump", 0.9, 0.0), 1.0)
	await _one("dry_click -> trigger_click (0.85)", func(): sound.play("dry_click", 0.85, 0.0), 0.8)


## Ruth walks and runs over each ground that the town has a straight stretch of, and the footsteps are measured.
func _steps() -> void:
	lines.append("-- footsteps (Ruth walking at 3.2 tiles/s, then running at 4.64; the soundscape's own _foot_tick, a stride of 0.85 tiles)")
	var segs := _segments()
	for g in Foley.GROUNDS:
		if not segs.has(g):
			lines.append("%-28s (the town has no straight stretch of it)" % g)
			continue
		for run in [false, true]:
			await _walk_ruth(g, segs[g], run)


func _segments() -> Dictionary:
	var out := {}
	var w := int(world.W)
	var h := int(world.H)
	var need := 7
	for y in range(2, h - 2):
		var run_g := ""
		var start := 0
		for x in range(2, w - 2):
			var g := Foley.ground_at(world, x + 0.5, y + 0.5)
			var open: bool = not world.is_solid(world.solid_p, x + 0.5, y + 0.5)
			if g == run_g and open:
				if x - start + 1 >= need and not out.has(g):
					out[g] = [Vector2(start + 0.5, y + 0.5), Vector2(x + 0.5, y + 0.5)]
			else:
				run_g = g if open else ""
				start = x
	return out


func _walk_ruth(g: String, seg: Array, run: bool) -> void:
	_silence()
	cap.clear_buffer()
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var speed := 4.64 if run else 3.2
	me.x = a.x
	me.y = a.y
	me.set_meta("sprint_lean", 1.0 if run else 0.0)
	game.cam_center = Vector2(me.x, me.y)
	var dir := 1.0
	var t0 := Time.get_ticks_msec()
	var all := PackedVector2Array()
	var last := Time.get_ticks_msec()
	var amb_low := 0.0
	while float(Time.get_ticks_msec() - t0) / 1000.0 < 3.2:
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := minf(float(now - last) / 1000.0, 0.05)
		last = now
		me.x += dir * speed * dt
		if me.x > b.x:
			me.x = b.x
			dir = -1.0
		elif me.x < a.x:
			me.x = a.x
			dir = 1.0
		game.cam_center = Vector2(me.x, me.y)
		amb_low = minf(amb_low, AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")))
		var n := cap.get_frames_available()
		if n > 0:
			all.append_array(cap.get_buffer(n))
	var steps := int(sc.played.get("step", 0))
	lines.append("%-28s %s   (step voices so far %d; the Ambience bus dipped to %.2f dB)" % ["%s %s" % [g, "RUN" if run else "walk"], _measure(all), steps, amb_low])
	me.set_meta("sprint_lean", 0.0)
	_silence()


func _dead() -> void:
	lines.append("-- the dead (a walker 4 tiles from Ruth, walking away at 0.9 tiles/s; a limper; a brute; the bite's wind-up)")
	var at := Vector2(me.x, me.y)
	game.cam_center = at
	for variant in ["walker on earth", "limper", "brute"]:
		_silence()
		var z = sim.spawn(at.x + 4.0, at.y, "wander", "brute" if variant == "brute" else "walker")
		z.limp = variant == "limper"
		cap.clear_buffer()
		var t0 := Time.get_ticks_msec()
		var all := PackedVector2Array()
		var last := Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - t0) / 1000.0 < 4.0:
			await process_frame
			sc.life._idle_t = 99.0    # (an idle groan would be heard in the middle of the measure: it is a scenario of its own, `crowd`)
			var now := Time.get_ticks_msec()
			var dt := minf(float(now - last) / 1000.0, 0.05)
			last = now
			z.x += 0.9 * dt
			var n := cap.get_frames_available()
			if n > 0:
				all.append_array(cap.get_buffer(n))
		lines.append("%-28s %s   (dead steps %d)" % ["dead step: " + variant, _measure(all), int(sc.life.played.get("dead_step", 0))])
		sim.zombies.erase(z)
	# the wind-up: a dead one at its bite
	for kind in ["walker", "runner", "brute"]:
		_silence()
		var z2 = sim.spawn(at.x + 2.5, at.y + 1.0, "attack", kind)
		z2.attack_t = 0.7
		cap.clear_buffer()
		var all2 := PackedVector2Array()
		var t1 := Time.get_ticks_msec()
		var fired := false
		while float(Time.get_ticks_msec() - t1) / 1000.0 < 1.6:
			await process_frame
			sc.life._idle_t = 99.0
			if not fired and float(Time.get_ticks_msec() - t1) / 1000.0 > 0.35:
				z2.attack_t = 0.40    # (the rules count it down; here it falls under the wind-up mark in one step)
				fired = true
			var n2 := cap.get_frames_available()
			if n2 > 0:
				all2.append_array(cap.get_buffer(n2))
		lines.append("%-28s %s   (growls %d)" % ["wind-up growl: " + kind, _measure(all2), int(sc.life.played.get("growl", 0))])
		sim.zombies.erase(z2)


func _voices() -> void:
	lines.append("-- voices of the dead (3 tiles away unless it says; the soundscape's own groan and roar)")
	var cam := Vector2(me.x, me.y)
	game.cam_center = cam
	# each wind-up voice by itself, at 2.5 tiles, at the level the code gives it (a mean of the jitter: no jitter here)
	for item in [["growl", "voice:zgrowl", "growl"], ["brute growl", "voice:zbrute_growl", "brute_growl"], ["runner hiss", "voice:zrun_hiss", "hiss"], ["runner screech", "voice:zrun_screech", "screech"]]:
		var key: String = item[1]
		var lvl: String = item[2]
		var label: String = item[0]
		for rep in 2:
			var idx := rep
			await _one("%s #%d at 2.5 tiles" % [label, rep], func():
				sc.play_at("growl", sc.group(key)[idx % sc.group(key).size()], cam + Vector2(2.5, 0.0), cam, float(Foley.LEVEL_DB[lvl]), 1.0, 10.0, 14.0, Buses.category_bus(Buses.VOICES)), 1.0)
	for d in [3.0, 8.0, 14.0, 20.0, 30.0]:
		for rep in 3:
			var dd: float = d
			await _one("groan at %d tiles #%d" % [int(d), rep], func(): sc.groan_play(cam + Vector2(dd, 0.0), "walker", false, cam), 1.7)
	await _one("groan (stray) at 6 tiles", func(): sc.groan_play(cam + Vector2(6.0, 0.0), "walker", true, cam), 1.7)
	await _one("brute roar at 6 tiles", func():
		sc.play_at("roar", sc.streams["roar"][0], cam + Vector2(6.0, 0.0), cam, float(Foley.LEVEL_DB["roar"]), 1.0, 100.0, 52.0, "SFX", 1.5), 2.4)
	await _one("brute roar at 20 tiles", func():
		sc.play_at("roar", sc.streams["roar"][0], cam + Vector2(20.0, 0.0), cam, float(Foley.LEVEL_DB["roar"]), 1.0, 100.0, 52.0, "SFX", 1.5), 2.4)


func _ruth() -> void:
	lines.append("-- Ruth")
	var cam := Vector2(me.x, me.y)
	game.cam_center = cam
	for i in 3:
		sc.last_groan_t = -100.0
		await _one("pain (bitten) #%d" % i, func():
			sc.life._pain_t = -100.0
			sc.life.on_bite({"who": String(me.id)}), 1.2)
	var sprint = sim.avatar.sprint
	sprint.stamina = 0.08
	sprint.active = true
	await _one("breath, sprint tank at 8 percent", func(): sc.life._breath_t = 0.0, 3.0)
	sprint.stamina = 0.25
	await _one("breath, tank at 25 percent", func(): sc.life._breath_t = 0.0, 3.0)
	sprint.stamina = 1.0
	sprint.active = false


func _weather() -> void:
	lines.append("-- thunder (on the Rain bus at Foley.thunder_db, open air and under a roof)")
	for case in [[0.0, 0.0], [0.2, 0.0], [0.5, 0.0], [0.8, 0.0], [1.0, 0.0], [0.0, 1.0], [0.5, 1.0]]:
		var far: float = case[0]
		var inside: float = case[1]
		Buses.set_rain_muffle(inside)
		var key := Foley.thunder_key(far)
		var list := Foley.load_group(key)
		var p := AudioStreamPlayer.new()
		p.stream = list[0]
		p.bus = Buses.rain_bus()
		p.volume_db = Foley.thunder_db(far, inside)
		root.add_child(p)
		_silence()
		cap.clear_buffer()
		p.play()
		var got := await _record(5.0)
		p.queue_free()
		lines.append("%-28s %s" % ["thunder far %.1f roof %.0f (%s)" % [far, inside, key.get_slice(":", 1)], _measure(got)])
	Buses.set_rain_muffle(0.0)


func _rain() -> void:
	lines.append("-- the rain bed (the Rain bus; the soundscape plays it at sound_level x 0.9: a drizzle 0.57, a steady rain 1.14, a storm 1.9)")
	for case in [["drizzle", 0.57], ["steady rain", 1.14], ["storm", 1.9]]:
		for inside in [0.0, 1.0]:
			Buses.set_rain_muffle(inside)
			_silence()
			var lvl: float = case[1]
			sc.bed_level["rain"] = lvl
			sc._bed("rain", lvl * 0.9)
			cap.clear_buffer()
			var got := await _record(3.0)
			lines.append("%-28s %s" % ["%s %s" % [case[0], "under a roof" if inside > 0.5 else "outdoors"], _measure(got)])
			sc.bed_level["rain"] = 0.0
			sc._bed("rain", 0.0)
	Buses.set_rain_muffle(0.0)


func _beds() -> void:
	lines.append("-- ambience beds (as the soundscape and sound.gd set them)")
	_silence()
	sound.wind.volume_db = linear_to_db(0.8)
	sound.wind.play()
	cap.clear_buffer()
	var got := await _record(3.0)
	lines.append("%-28s %s" % ["wind (day, level 0.8)", _measure(got)])
	sound.wind.stop()
	sc.bed_level["night_bed"] = 1.0
	sc._bed("night_bed", 0.85)
	cap.clear_buffer()
	got = await _record(3.0)
	lines.append("%-28s %s" % ["night bed (level 0.85)", _measure(got)])
	sc._bed("night_bed", 0.0)
	# the moan as sound.gd sets it (the horde at full: its level 1.0 and the SOUND pass's trim)
	sound.set_ambience(0.0, 1.0, 10.0)
	sound.wind.stop()
	sound.crickets.stop()
	sc._bed("night_bed", 0.0)
	cap.clear_buffer()
	got = await _record(3.0)
	lines.append("%-28s %s" % ["horde moan (1.0, trimmed)", _measure(got)])
	sound.moan.stop()
	sound.set_ambience(0.0, 0.0, 10.0)
	sound.wind.volume_db = linear_to_db(0.8)
	sound.wind.play()


func _music() -> void:
	lines.append("-- music (the stems at full, on the Music bus)")
	for name in ["mus_outdoors", "mus_indoors", "mus_night_base", "mus_fortress_base"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.wav" % name)
		p.bus = "Music"
		root.add_child(p)
		_silence()
		cap.clear_buffer()
		p.play(10.0)
		var got := await _record(3.0)
		p.queue_free()
		lines.append("%-28s %s" % [name, _measure(got)])


func _ui() -> void:
	lines.append("-- menu sounds")
	await _one("ui_click", func(): sound.ui("ui_click", 1.0, 0.0), 0.6)
	await _one("ui_confirm", func(): sound.ui("ui_confirm", 1.0, 0.0), 1.0)
	await _one("ui_notify (0.6)", func(): sound.ui("ui_notify", 0.6, 0.0), 1.4)
	await _one("bell chime (ring 1.0)", func(): sc.ring("chime"), 3.0)
	await _one("dusk bell, first toll", func(): sc._toll("bell:dusk", 1.0), 3.0)


## The ambience bus dips under a loud shot (Buses.ambience_duck_for): the wind plays, then a shot, and the dip is read off the bus.
func _duck() -> void:
	lines.append("-- ducking under gunfire")
	_silence()
	sound.wind.volume_db = linear_to_db(0.8)
	sound.wind.play()
	await _wait(0.6)
	var i := AudioServer.get_bus_index("Ambience")
	var before := AudioServer.get_bus_volume_db(i)
	var worst := before
	sound.play("blast_out", 1.0, 0.0)
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) < 1500.0:
		await process_frame
		worst = minf(worst, AudioServer.get_bus_volume_db(i))
	await _wait(1.2)
	lines.append("Ambience bus: %.2f dB before the shot, %.2f dB at the deepest, %.2f dB a moment after" % [before, worst, AudioServer.get_bus_volume_db(i)])
	# what else dips it: the other sounds that are loud, each by itself (the SFX bus's peak is what is read)
	var cam := Vector2(me.x, me.y)
	game.cam_center = cam
	var cases := [
		["a thud and a wet kill (SFX)", func(): sound.play("melee_hit", 0.95, 0.0); sound.play("melee_kill", 0.8, 0.0)],
		["a dusk bell toll (SFX)", func(): sc._toll("bell:dusk", 1.0)],
		["a groan one tile away (Voices)", func(): sc.groan_play(cam + Vector2(1.0, 0.0), "walker", false, cam)],
		["a brute's growl one tile away (Voices)", func(): sc.play_at("growl", sc.group("voice:zbrute_growl")[0], cam + Vector2(1.0, 0.0), cam, float(Foley.LEVEL_DB["brute_growl"]), 1.0, 10.0, 14.0, Buses.category_bus(Buses.VOICES))],
		["Ruth's running step on tile (Steps)", func(): sc.play_at("step", sc.group("fs:tile:run")[0], cam, cam, float(Foley.LEVEL_DB["step_run"]), 1.0, 10.0, 14.0, Buses.category_bus(Buses.STEPS))],
	]
	for c in cases:
		_silence()
		sound.wind.volume_db = linear_to_db(0.8)
		sound.wind.play()
		await _wait(1.0)
		var w := AudioServer.get_bus_volume_db(i)
		(c[1] as Callable).call()
		var t1 := Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - t1) < 1200.0:
			await process_frame
			w = minf(w, AudioServer.get_bus_volume_db(i))
		lines.append("  %-42s Ambience dipped to %.2f dB" % [c[0], w])
	_silence()


## Idle groans: six of the dead wander 8 to 20 tiles from Ruth for 40 seconds (day, then night): how many groans are heard, how far apart, and the most voices at once.
func _idle() -> void:
	lines.append("-- idle groans (six dead wandering 8 to 20 tiles from Ruth; the rules' own groan events are not made here: these are the soundscape's idle ones)")
	var cam := Vector2(me.x, me.y)
	game.cam_center = cam
	for phase in ["day", "night"]:
		_silence()
		sim.phase = phase
		var zs: Array = []
		for i in 6:
			zs.append(sim.spawn(cam.x + 8.0 + 2.4 * i, cam.y + (i - 3) * 1.5, "wander"))
		sc.played.erase("groan")
		sc.life.played.erase("idle_groan")
		var stamps: Array = []
		var seen := 0
		var t0 := Time.get_ticks_msec()
		var max_groans := 0
		while float(Time.get_ticks_msec() - t0) / 1000.0 < 40.0:
			await process_frame
			var n := int(sc.life.played.get("idle_groan", 0))
			if n > seen:
				seen = n
				stamps.append(snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.1))
			max_groans = maxi(max_groans, sc._count("groan"))
		lines.append("%-6s 40 s: %d idle groans at %s s; most groan voices at once %d" % [phase, seen, str(stamps), max_groans])
		for z in zs:
			sim.zombies.erase(z)
	sim.phase = "day"
	_silence()


## The worst case: a storm, the music, Ruth running with her tank empty, a shot every 0.45 s, thirty of the dead at their bites (the rules' count-down of `attack_t`, done here by hand), idle groans on.
## What the voices do (never more than the cap), and what the master does (the peak under the limiter's ceiling).
func _crowd() -> void:
	lines.append("-- the worst case (storm, music, a run with the tank empty, a shot every 0.45 s, 30 of the dead at their bites for 8 s)")
	_silence()
	var cam := Vector2(me.x, me.y)
	game.cam_center = cam
	var dead: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, 11.0)
		var z = sim.spawn(cam.x + cos(a) * r, cam.y + sin(a) * r, "attack", ["walker", "walker", "runner", "brute"][i % 4])
		z.attack_t = rng.randf_range(0.2, 1.3)
		dead.append(z)
	var music := AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/mus_fortress_base.wav")
	music.bus = "Music"
	root.add_child(music)
	music.play(10.0)
	sc.bed_level["rain"] = 1.9
	sc._bed("rain", 1.9 * 0.9)
	var sprint = sim.avatar.sprint
	sprint.stamina = 0.1
	sprint.active = true
	me.set_meta("sprint_lean", 1.0)
	cap.clear_buffer()
	var all := PackedVector2Array()
	var t0 := Time.get_ticks_msec()
	var last := t0
	var next_shot := 0.0
	var max_voices := 0
	var max_groans := 0
	var amb_deepest := 0.0
	var ai := AudioServer.get_bus_index("Ambience")
	while float(Time.get_ticks_msec() - t0) / 1000.0 < 8.0:
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := minf(float(now - last) / 1000.0, 0.05)
		last = now
		var el := float(now - t0) / 1000.0
		for z in dead:
			z.attack_t -= dt
			if z.attack_t <= 0.0:
				z.attack_t = 1.3
		if el >= next_shot:
			next_shot = el + 0.45
			sound.gunfight.shot({"gun": "shotgun", "x": cam.x, "y": cam.y}, cam)
		max_voices = maxi(max_voices, sc.voices_playing())
		max_groans = maxi(max_groans, sc._count("groan"))
		amb_deepest = minf(amb_deepest, AudioServer.get_bus_volume_db(ai))
		var n := cap.get_frames_available()
		if n > 0:
			all.append_array(cap.get_buffer(n))
	lines.append("%-28s %s" % ["worst case, 8 s, limiter on", _measure(all)])
	AudioServer.set_bus_effect_enabled(0, 0, false)
	lines.append("  positional voices at most %d of %d (groans at most %d), growls %d, dead steps %d, idle groans %d, dropped for the cap %d, Ambience dipped to %.2f dB" % [
		max_voices, sc.voices.size(), max_groans, int(sc.life.played.get("growl", 0)), int(sc.life.played.get("dead_step", 0)), int(sc.life.played.get("idle_groan", 0)), sc.dropped, amb_deepest])
	# and again with the master's limiter switched off, to see how far over its ceiling the sum would go
	cap.clear_buffer()
	var raw := PackedVector2Array()
	var t1 := Time.get_ticks_msec()
	last = t1
	next_shot = 0.0
	while float(Time.get_ticks_msec() - t1) / 1000.0 < 6.0:
		await process_frame
		var now2 := Time.get_ticks_msec()
		var dt2 := minf(float(now2 - last) / 1000.0, 0.05)
		last = now2
		var el2 := float(now2 - t1) / 1000.0
		for z in dead:
			z.attack_t -= dt2
			if z.attack_t <= 0.0:
				z.attack_t = 1.3
		if el2 >= next_shot:
			next_shot = el2 + 0.45
			sound.gunfight.shot({"gun": "shotgun", "x": cam.x, "y": cam.y}, cam)
		var n3 := cap.get_frames_available()
		if n3 > 0:
			raw.append_array(cap.get_buffer(n3))
	lines.append("%-28s %s" % ["worst case, 6 s, limiter OFF", _measure(raw)])
	AudioServer.set_bus_effect_enabled(0, 0, true)
	for z in dead:
		sim.zombies.erase(z)
	music.queue_free()
	sc.bed_level["rain"] = 0.0
	sprint.stamina = 1.0
	sprint.active = false
	me.set_meta("sprint_lean", 0.0)
	_silence()


# ----------------------------------------------------------------------------------------------- tools --

func _silence() -> void:
	for p in sound.players:
		p.stop()
	for p in sound.ui_players:
		p.stop()
	for v in sc.voices:
		v.p.stop()
	for b in sc.bells:
		b.stop()
	for key in sc.beds:
		sc.beds[key].stop()
	sound.wind.stop()
	sound.crickets.stop()
	sound.moan.stop()
	sc._later.clear()


func _wait(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await process_frame


## Silence, one thing played, `seconds` recorded, one line.
func _one(label: String, play: Callable, seconds: float) -> void:
	_silence()
	await _wait(0.15)
	cap.clear_buffer()
	play.call()
	var got := await _record(seconds)
	lines.append("%-40s %s" % [label, _measure(got)])


func _record(seconds: float) -> PackedVector2Array:
	var all := PackedVector2Array()
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await process_frame
		var n := cap.get_frames_available()
		if n > 0:
			all.append_array(cap.get_buffer(n))
	var n2 := cap.get_frames_available()
	if n2 > 0:
		all.append_array(cap.get_buffer(n2))
	return all


func _measure(frames: PackedVector2Array) -> String:
	if frames.is_empty():
		return "(nothing captured)"
	var peak := 0.0
	var over := 0
	for f in frames:
		var a := maxf(absf(f.x), absf(f.y))
		peak = maxf(peak, a)
		if a > 1.0:
			over += 1
	return "peak %6.1f dBFS   M-max %6.1f LUFS%s" % [linear_to_db(maxf(peak, 1e-9)), _mmax(frames), ("   (%d samples over full scale)" % over) if over > 0 else ""]


## The loudest 400 ms momentary loudness (K-weighted, both channels summed in power), stepped every 100 ms.
func _mmax(frames: PackedVector2Array) -> float:
	var n := frames.size()
	var kl := _kweight(frames, 0)
	var kr := _kweight(frames, 1)
	var win := int(0.4 * rate)
	var hop := int(0.1 * rate)
	var best := -200.0
	var s := -int(0.3 * rate)
	# running sums of the squares, so that a window is two look-ups
	var cs := PackedFloat64Array()
	cs.resize(n + 1)
	var acc := 0.0
	for i in n:
		acc += kl[i] * kl[i] + kr[i] * kr[i]
		cs[i + 1] = acc
	while s + win <= n + int(0.4 * rate):
		var a := clampi(s, 0, n)
		var b := clampi(s + win, 0, n)
		var ms: float = (cs[b] - cs[a]) / float(win)
		best = maxf(best, -0.691 + 10.0 * log(maxf(ms, 1e-14)) / log(10.0))
		s += hop
	return best


## The K-weighting (the standard's two biquads for 48 kHz; at 44.1 kHz they are only roughly right, to a few tenths of a decibel for these sounds).
func _kweight(frames: PackedVector2Array, ch: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames.size())
	var b1 := [1.53512485958697, -2.69169618940638, 1.19839281085285]
	var a1 := [1.0, -1.69065929318241, 0.73248077421585]
	var b2 := [1.0, -2.0, 1.0]
	var a2 := [1.0, -1.99004745483398, 0.99007225036621]
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var u1 := 0.0
	var u2 := 0.0
	var v1 := 0.0
	var v2 := 0.0
	for i in frames.size():
		var x: float = frames[i].x if ch == 0 else frames[i].y
		var y: float = b1[0] * x + b1[1] * x1 + b1[2] * x2 - a1[1] * y1 - a1[2] * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		var z: float = b2[0] * y + b2[1] * u1 + b2[2] * u2 - a2[1] * v1 - a2[2] * v2
		u2 = u1
		u1 = y
		v2 = v1
		v1 = z
		out[i] = z
	return out
