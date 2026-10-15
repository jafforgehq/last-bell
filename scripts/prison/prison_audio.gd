## ROUND 12: SOUND AND ATMOSPHERE of the prison game. One node, made by prison_game.gd after the sound node, that adds what the shared sound code (scripts/audio/sound.gd, soundscape.gd) does not
## know about the prison: a layered score mixed by the state of the game, the weather and the places' own ambience, footsteps by surface for the crew and the dead, doors, searching and
## building, the echo of the guns off the compound's walls, a few non-verbal voices, a heartbeat and muffled hearing when Ruth is nearly dead. Everything it plays is in assets/audio/prison/ (made by
## tools/make_prison_audio.py: arithmetic only, no samples, no services); the older sounds (the guns, the groans, the bell, the footsteps files fs_*, the menu clicks) are still the sound node's.
##
## It reads the game, it does not change it: `on_event(e)` gets the rules' events from `_step`, `on_death(m)` a crew member's death, and the rest it senses five times a second (`_sense`): the
## phase and mode, the hour, the siege (attacking, the dead at the wall, the weakest segment's hp), how many dead are awake and after Ruth, how far she is from the exit, her hp, whether she is
## under a roof, the ground under her feet. The music is NINE LOOPS (stems) that are all playing all the time, in step (the 16 s ones and the 32 s ones start in the same frame), and what the game
## moves is their volumes (a layer comes in over about 2 s and goes out over 4: no clicks). A stinger (a segment falls, someone dies, the dawn) plays over them and dips them.
##
## MUSIC STEMS (all D minor but `explore`): drone (always, the floor), motif (the day: a slow piano line), drip (dusk and night: sparse bells and drips), pulse (night, the siege: a heartbeat and a
## bass), perc (the siege's drums), danger (the siege near its worst: dissonant strings), explore (the clear phase), raid (out on a raid, more the farther from the exit), chase (more than CHASE_N dead
## awake and coming for her: the music breaks into a driving beat).
## Flags: --audiolog (prints each sound as it starts, a summary of counts and bus peaks at the end of a --frames=N run), --noprisonaudio (this node does nothing), --nomusic, --norain, --rain[=0..1] (rain
## all the time), --audiodump=DIR (writes every prison file as the engine has loaded it, to compare with the source).
extends Node

const Buses := preload("res://scripts/audio/buses.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")

const DIR := "res://assets/audio/prison/"
const OLD := "res://assets/audio/"
const TILE := 64.0
const STEMS_16 := ["drone", "drip", "pulse", "perc", "danger", "raid", "chase"]
const STEMS_32 := ["motif", "explore"]
## How loud a stem is at gain 1 in decibels (the files are levelled alike; these set the mix of a mood).
const STEM_DB := {"drone": 0.0, "motif": 0.0, "drip": 0.0, "pulse": 0.0, "perc": 0.0, "danger": -1.0, "explore": 0.0, "raid": 0.0, "chase": -1.0}
const CHASE_N := 4
const CHASERS := ["approach", "attack", "hunt"]
const STRIDE := 0.8
const SENSE := 0.2
const MAX_STARTS_PER_SEC := 18
const POOL := 14
const POOL2 := 12
const PEN := Vector2(48.0, 62.5)
const CANTEEN := Vector2(76.0, 18.0)
const RADIO := Vector2(58.8, 36.6)
const LAUNDRY := Vector2(18.5, 46.5)
const STOVE := Vector2(78.5, 11.0)
## terrain id (scripts/prison/prison_base.gd T_*) -> the ground's name
const GROUND := {1: "pave", 2: "pave", 3: "grass", 4: "grass", 5: "dirt", 7: "tile", 11: "tile", 12: "pave", 13: "dirt", 20: "pave", 21: "tile", 22: "pave"}
const STEP_FILES := {"pave": "fs_pave", "grass": "fs_grass", "dirt": "fs_dirt", "gravel": "fs_gravel", "tile": "fs_tile", "wood": "fs_wood"}
const VOICES := ["male", "female", "old"]

var game
var enabled := true
var music_on := true
var rain_force := -1.0
var norain := false
var _rng := RandomNumberGenerator.new()
var _cache := {}
var _t := 0.0
var _slow := 0.0
var _frames := 0
var _music := {}
var _gain := {}
var _loading: Array = []
var _started := false
var _stingers: Array = []
var _beds := {}
var _pool: Array = []
var _pool2: Array = []
var _root2d: Node2D
var _fires: Array = []
var _floods: Array = []
var _spot := {}
var s := {"mode": "base", "phase": "clear", "night": 0.0, "tod": 8.0, "attacking": false, "threat": 0.0, "chase": 0.0, "exit": 0.0, "hp": 1.0, "indoor": 0.0, "ground": "pave", "fence_n": 0, "fence_hp": 1.0}
var _threat := 0.0
var _chase := 0.0
var _indoor := 0.0
var _duck := 0.0
var _duck_want := 0.0
var _duck_hold := 0.0
var _rain := 0.0
var _wind := 0.35
var _muffle := 0.0
var _deaf := 0.0
var _heart_t := 0.0
var _segs_down := {}
var _was_attacking := false
var _dawn_at := -1.0
var _death_at := -99.0
var _last := {}
var _starts: Array = []
var _stride := {}
var _prev_pos := {}
var _prev_hp := {}
var _prev_down := {}
var _bark_at := -9.0
var _bark_who := {}
var _next := {"moan": 8.0, "owl": 30.0, "crow": 20.0, "clatter": 0.0, "whistle": 60.0, "cough": 50.0, "chain": 0.0, "warn": 0.0}
var _food_warned := false
var _pack_open := false
var _store_ammo := -1.0
var _log := false
var _counts := {}
var _peaks := {}
var _sec_counts := {}
var _max_per_sec := 0
var _dump := ""
var _had_pack_state := false
var _tour: Array = []
var _tour_t := 3.0
var _tour_player: AudioStreamPlayer


func setup(g) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "PrisonAudio"
	_log = g.args.has("audiolog")
	enabled = not g.args.has("noprisonaudio")
	music_on = not g.args.has("nomusic")
	norain = g.args.has("norain")
	if g.args.has("rain"):
		rain_force = clampf(float(g.args.rain), 0.0, 1.0)
	_rng.seed = 1212
	_dump = String(g.args.get("audiodump", ""))
	if not enabled:
		return
	_root2d = Node2D.new()
	_root2d.name = "Audio2D"
	g.add_child(_root2d)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in POOL2:
		var q := AudioStreamPlayer2D.new()
		_root2d.add_child(q)
		_pool2.append(q)
	for i in 2:
		var st := AudioStreamPlayer.new()
		st.bus = "Music"
		add_child(st)
		_stingers.append(st)
	var names: Array = []
	for n in STEMS_16 + STEMS_32:
		names.append("pm_" + n)
	for n in names:
		_loading.append(n)
	_make_beds()
	if g.args.has("audiotour"):
		_tour = []
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".wav.import"):
				_tour.append(f.trim_suffix(".wav.import"))
		_tour.sort()
	if _dump != "":
		_dump_all()


## ------------------------------------------------------------------------------ loading

func _stream(key: String, dir := DIR) -> AudioStream:
	var k := dir + key
	if _cache.has(k):
		return _cache[k]
	var path := "%s%s.wav" % [dir, key]
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
	_cache[k] = st
	return st


func _looped(key: String) -> AudioStreamWAV:
	var st := _stream(key) as AudioStreamWAV
	if st != null:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	return st


func _dump_all() -> void:
	DirAccess.make_dir_recursive_absolute(_dump)
	var n := 0
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".wav.import"):
			var key := f.trim_suffix(".wav.import")
			var st := _stream(key) as AudioStreamWAV
			if st != null:
				var err := st.save_to_wav("%s/%s.wav" % [_dump, key])
				if err == OK:
					n += 1
				elif n == 0:
					print("AUDIODUMP ", key, " not written: error ", err, " (format ", st.format, ")")
	print("AUDIODUMP wrote ", n, " files to ", _dump)


func _make_beds() -> void:
	var rb := Buses.rain_bus()
	_bed("rain_roof", "pa_rain_roof", rb)
	_bed("rain_conc", "pa_rain_concrete", rb)
	_bed("rain_grass", "pa_rain_grass", rb)
	_bed("wind_low", "pa_wind_low", "Outside")
	_bed("wind_gust", "pa_wind_gust", "Outside")
	_bed("room", "pa_room", "Ambience")
	for i in 4:
		var f := _bed2d("fire%d" % i, "pa_fire", "Ambience", 13.0)
		_fires.append(f)
	for i in 3:
		_floods.append(_bed2d("flood%d" % i, "pa_buzz", "Ambience", 10.0))
	_spot["flutter"] = _bed2d("flutter", "pa_flutter", "Ambience", 9.0)
	_spot["static"] = _bed2d("static", "pa_static", "Ambience", 8.0)


func _bed(key: String, file: String, bus: String) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Ambience"
	p.volume_db = -80.0
	add_child(p)
	_beds[key] = {"p": p, "file": file, "g": 0.0, "want": 0.0, "db": 0.0}


func _bed2d(key: String, file: String, bus: String, reach: float) -> Dictionary:
	var p := AudioStreamPlayer2D.new()
	p.bus = bus
	p.max_distance = reach * TILE
	p.attenuation = 1.8
	p.volume_db = -80.0
	_root2d.add_child(p)
	var d := {"p": p, "file": file, "g": 0.0, "want": 0.0, "db": 0.0, "at": Vector2.ZERO, "reach": reach}
	_beds[key] = d
	return d


## ------------------------------------------------------------------------------ the frame

func _process(dt: float) -> void:
	if not enabled or game == null or game.run == null:
		return
	_t += dt
	_frames += 1
	if not _loading.is_empty():
		var n: String = _loading.pop_front()
		_looped(n)    # (one a frame: no load stalls)
		if _loading.is_empty():
			_start_music()
	_slow -= dt
	if _slow <= 0.0 and not get_tree().paused:
		_slow = SENSE
		_sense(SENSE)
	if not _tour.is_empty():
		_tour_step(dt)
	_music_update(dt)
	_beds_update(dt)
	_hearing(dt)
	if not get_tree().paused:
		_steps(dt)
		_life(dt)
	if _log:
		_log_frame()


func _start_music() -> void:
	if _started or not music_on:
		return
	_started = true
	for n in STEMS_16 + STEMS_32:
		var st := _looped("pm_" + n)
		if st == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.stream = st
		p.volume_db = -80.0
		add_child(p)
		_music[n] = p
		_gain[n] = 0.0
	for n in _music:
		(_music[n] as AudioStreamPlayer).play()    # (all in one frame: the stems stay in step)


## ------------------------------------------------------------------------------ sensing

func _sense(dt: float) -> void:
	var p = game.run.avatar_p
	var me := Vector2(p.x, p.y)
	s.mode = game.mode
	s.phase = game.phase
	s.tod = game.tod
	s.night = game._night_of(game.tod) if game.mode == "base" else 0.55
	s.hp = clampf(float(p.hp) / 100.0, 0.0, 1.0)
	var siege = game.siege
	s.attacking = siege != null and siege.attacking and game.mode == "base" and game.phase == "managed"
	# the fence: dead at the wall, the weakest segment
	var at_wall := 0
	var weakest := 1.0
	if siege != null and game.mode == "base" and game.phase == "managed":
		for sg in siege.segs:
			at_wall += int(sg.push)
			weakest = minf(weakest, float(sg.hp) / maxf(1.0, float(sg.max)))
			var down := float(sg.hp) <= 0.0
			if down and not _segs_down.has(sg.name):
				_segs_down[sg.name] = true
				if _t > 3.0:
					stinger("pst_fall", -3.0, 4.0)
			elif not down:
				_segs_down.erase(sg.name)
	s.fence_n = at_wall
	s.fence_hp = weakest
	var want := 0.0
	if s.attacking:
		want = clampf(0.2 + float(at_wall) / 10.0 * 0.5 + (1.0 - weakest) * 0.4, 0.0, 1.0)
		if not _segs_down.is_empty():
			want = maxf(want, 0.75)
	_threat = move_toward(_threat, want, (0.5 if want > _threat else 0.04) * dt)
	s.threat = _threat
	if _was_attacking and not s.attacking and game.phase == "managed":
		_dawn_at = _t + 2.5
	_was_attacking = s.attacking
	if _dawn_at > 0.0 and _t >= _dawn_at:
		_dawn_at = -1.0
		stinger("pst_dawn", -4.0, 8.0)
	# the dead after her
	var chasing := 0
	var awake := 0
	for z in game.run.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		awake += 1
		if CHASERS.has(z.state):
			var dx: float = z.x - me.x
			var dy: float = z.y - me.y
			if dx * dx + dy * dy < 196.0:
				chasing += 1
	var cw := smoothstep(CHASE_N - 0.5, CHASE_N + 4.0, float(chasing))
	if game.mode == "base" and game.phase == "managed":
		cw = 0.0    # (at the wall the siege layers do it)
	_chase = move_toward(_chase, cw, (0.4 if cw > _chase else 0.07) * dt)
	s.chase = _chase
	s.awake = awake
	var ex := 0.0
	if game.mode == "raid" and not game.exits.is_empty():
		ex = 999.0
		for e in game.exits:
			ex = minf(ex, me.distance_to(Vector2(e)))
	s.exit = ex
	var h: int = TownGen.house_at(game.town, p.x, p.y) if game.town != null else -1
	_indoor = move_toward(_indoor, 1.0 if h >= 0 else 0.0, 3.0 * dt)
	s.indoor = _indoor
	s.ground = _ground_at(me.x, me.y)
	_weather(dt)
	_places()
	_ducking(dt)
	_watch_people(me)
	_watch_state()
	if _log:
		for b in ["Master", "Music", "Ambience", "SFX", "Voices", "Steps", "Outside", "Rain"]:
			var i := AudioServer.get_bus_index(b)
			if i >= 0:
				_peaks[b] = maxf(float(_peaks.get(b, -200.0)), _peak(i))


func _peak(bus_idx: int) -> float:
	return maxf(AudioServer.get_bus_peak_volume_left_db(bus_idx, 0), AudioServer.get_bus_peak_volume_right_db(bus_idx, 0))


func _ground_at(x: float, y: float) -> String:
	var w = game.world
	if w == null:
		return "pave"
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= w.W or ty >= w.H:
		return "grass"
	var g := String(GROUND.get(int(w.terrain[ty * w.W + tx]), "pave"))
	if g == "dirt" and _rain > 0.35:
		return "mud"
	return g


func _weather(dt: float) -> void:
	var day := int(floor(game.siege.abs_h / 24.0)) if game.siege != null else 0
	var h: float = game.tod
	var r := 0.0
	if rain_force >= 0.0:
		r = rain_force
	elif not norain:
		var a := _hash01(day * 7 + 3)
		if a < 0.4:
			var start := 9.0 + _hash01(day * 13 + 1) * 8.0
			var len_h := 3.0 + _hash01(day * 5 + 2) * 5.0
			r = smoothstep(start, start + 0.7, h) * (1.0 - smoothstep(start + len_h, start + len_h + 1.0, h)) * (0.45 + 0.55 * _hash01(day * 3 + 9))
	_rain = move_toward(_rain, r, 0.15 * dt)
	var gust := 0.5 + 0.5 * sin(_t * 0.07 + 1.3) * sin(_t * 0.031)
	var w := 0.3 + 0.25 * _hash01(day * 11 + 4) + 0.2 * gust + 0.3 * _rain
	_wind = move_toward(_wind, clampf(w, 0.0, 1.0), 0.1 * dt)


func _hash01(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 10000) / 10000.0


func _ducking(dt: float) -> void:
	var i := AudioServer.get_bus_index("SFX")
	var peak := -80.0
	if i >= 0:
		peak = _peak(i)
	var d := -clampf((peak + 14.0) * 0.3, 0.0, 6.0)
	if _duck_hold > 0.0:
		_duck_hold -= dt
		d = minf(d, _duck_want)
	_duck = d if d < _duck else move_toward(_duck, d, 6.0 * dt)


## Dips the music for a while (an alarm, a stinger): -4 dB or so for `secs`.
func duck(db: float, secs: float) -> void:
	_duck_want = minf(db, 0.0)
	_duck_hold = maxf(_duck_hold, secs)


func _watch_state() -> void:
	# low food: the warning, once while it stays low
	var food := float(game.stores.get("food", 99.0))
	if food < 8.0 and not _food_warned and game.phase == "managed" and game.mode == "base":
		_food_warned = true
		sfx("pu_warn_0", -6.0, 1.0, "UI")
	elif food > 14.0:
		_food_warned = false
	# the backpack opens and closes
	var open: bool = game.pack != null and game.pack.ui != null and game.pack.ui.is_open()
	if _had_pack_state and open != _pack_open:
		sfx("pu_pack_open" if open else "pu_pack_close", -8.0, 1.0, "UI")
	_pack_open = open
	_had_pack_state = true
	if game.alarm_t > 0.0 and _t - float(_last.get("alarm", -99.0)) > 24.0:
		_last["alarm"] = _t
		sfx("pu_alarm_0", -9.0, 1.0, "SFX")
		duck(-5.0, 3.0)
		bark("old", "effort", -2.0, null)


## ------------------------------------------------------------------------------ the score

func _music_update(dt: float) -> void:
	var tgt := _targets() if _started else {}
	var dlin := db_to_linear(_duck)
	for n in _music:
		var g: float = _gain[n]
		var w: float = tgt.get(n, 0.0)
		g += (w - g) * (1.0 - exp(-dt / (2.2 if w > g else 4.0)))
		_gain[n] = g
		var p: AudioStreamPlayer = _music[n]
		p.volume_db = linear_to_db(g * dlin) + float(STEM_DB.get(n, 0.0)) if g > 0.003 else -80.0


func _targets() -> Dictionary:
	var t := {}
	var n: float = s.night
	var c: float = s.chase
	if s.mode == "raid":
		var k := clampf(float(s.exit) / 60.0, 0.0, 1.0)
		t["raid"] = (0.4 + 0.6 * k) * (1.0 - 0.6 * c)
		t["drone"] = (0.15 + 0.35 * k) * (1.0 - 0.5 * c)
		t["drip"] = 0.7 * k * (0.4 + 0.6 * n) * (1.0 - c)
		t["pulse"] = 0.35 * smoothstep(0.5, 1.0, k) + 0.3 * c
		t["chase"] = c
		t["perc"] = 0.5 * c
		t["danger"] = 0.35 * c
	elif s.phase == "clear":
		t["explore"] = 0.85 * (1.0 - 0.75 * c)
		t["drone"] = 0.2 + 0.3 * c
		t["chase"] = c
		t["perc"] = 0.4 * c
		t["danger"] = 0.3 * c
		t["pulse"] = 0.3 * c
	else:
		var h: float = s.tod
		var dusk := smoothstep(16.5, 19.5, h) if h > 12.0 else 0.0
		var calm := 1.0 - n
		t["drone"] = 0.35 + 0.5 * n
		t["motif"] = calm * 0.85 * (1.0 - dusk)
		t["drip"] = maxf(dusk * 0.5, n * 0.85)
		t["pulse"] = n * 0.3
		if s.attacking:
			var th: float = s.threat
			t["drone"] = 0.7
			t["motif"] = 0.0
			t["pulse"] = 0.35 + 0.65 * th
			t["perc"] = smoothstep(0.3, 0.75, th)
			t["danger"] = smoothstep(0.55, 1.0, th)
			t["drip"] = float(t["drip"]) * (1.0 - 0.7 * th)
	return t


## A stinger over the music (a segment falls, someone dies, the dawn): `db` its level, `gap` seconds before the same one may play again.
func stinger(key: String, db: float, gap: float) -> void:
	if not enabled or not music_on:
		return
	if _t - float(_last.get(key, -99.0)) < gap:
		return
	var st := _stream(key)
	if st == null:
		return
	_last[key] = _t
	var pl: AudioStreamPlayer = _stingers[0]
	for q in _stingers:
		if not (q as AudioStreamPlayer).playing:
			pl = q
			break
	pl.stream = st
	pl.volume_db = db
	pl.play()
	duck(-4.5, minf(st.get_length() * 0.5, 5.0))
	_note(key)


## A crew member has died (prison_game.gd keep_corpse): the dark swell, once in a while, and the others' sobbing is left to the voices.
func on_death(m: Dictionary) -> void:
	if not enabled or _t - _death_at < 18.0:
		return
	_death_at = _t
	stinger("pst_death", -3.0, 10.0)


## ------------------------------------------------------------------------------ ambience

func _beds_update(dt: float) -> void:
	var rain := _rain
	var ind := _indoor
	var conc := 0.5 + 0.5 * (1.0 if String(s.ground) == "pave" or String(s.ground) == "tile" else 0.0)
	var w := _wind
	var out := 1.0 - ind
	_bed_want("rain_roof", rain * ind * 0.9)
	_bed_want("rain_conc", rain * out * conc * 0.9)
	_bed_want("rain_grass", rain * out * (1.5 - conc) * 0.9)
	_bed_want("wind_low", (0.2 + 0.6 * w) * (0.9 if s.mode == "base" else 1.0))
	_bed_want("wind_gust", clampf((w - 0.4) * 1.6, 0.0, 1.0))
	_bed_want("room", ind * 0.8)
	Buses.set_rain_muffle(ind)
	var oi := AudioServer.get_bus_index("Outside")
	if oi >= 0 and AudioServer.get_bus_effect_count(oi) > 0:
		var fx = AudioServer.get_bus_effect(oi, 0)
		if fx is AudioEffectLowPassFilter:
			fx.cutoff_hz = exp(lerpf(log(20500.0), log(1500.0), ind))
		AudioServer.set_bus_volume_db(oi, -4.0 * ind)
	for k in _beds:
		var b: Dictionary = _beds[k]
		var g: float = b.g
		g += (float(b.want) - g) * (1.0 - exp(-dt / 1.6))
		b.g = g
		var pl = b.p
		if g < 0.004:
			if pl.playing:
				pl.stop()
			continue
		if not pl.playing:
			var st := _looped(String(b.file))
			if st == null:
				continue
			pl.stream = st
			pl.play(_rng.randf() * st.get_length())
		pl.volume_db = linear_to_db(g) + float(b.get("db", 0.0))


func _bed_want(k: String, v: float) -> void:
	var b: Dictionary = _beds[k]
	b.want = v
	b.db = _BED_DB.get(k, -4.0)


const _BED_DB := {"rain_roof": -3.0, "rain_conc": -3.0, "rain_grass": -3.0, "wind_low": -6.0, "wind_gust": -6.0, "room": -4.0}


## The places that have a sound of their own: fires, the stove, floodlights, the line of washing, the radio. Each is a looping player at its spot, fading with the distance by the engine.
func _places() -> void:
	var base_mode: bool = game.mode == "base"
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var night := float(s.night)
	var lamp: float = game._lamp_of(game.tod)
	var spots: Array = []
	if base_mode and game.base != null:
		for f in game.base.fires:
			spots.append([Vector2(f), 0.8 * lamp, -3.0])
		if game.econ != null and game.econ.tier("kitchen") >= 1 and game.crew != null and game.crew._meal_window() >= 0:
			spots.append([STOVE, 0.7, -5.0])
	spots.sort_custom(func(a, b): return Vector2(a[0]).distance_squared_to(me) < Vector2(b[0]).distance_squared_to(me))
	for i in _fires.size():
		var d: Dictionary = _fires[i]
		if i < spots.size():
			d.at = spots[i][0]
			d.want = float(spots[i][1])
			d.db = float(spots[i][2])
			(d.p as AudioStreamPlayer2D).global_position = Vector2(d.at) * TILE
		else:
			d.want = 0.0
	# floodlights: the three nearest poles, on while the power is on at night
	var fl_on: bool = base_mode and game.phase == "managed" and game.econ != null and game.econ.tier("power") >= 1 and game.upg._lit() and night > 0.3
	var poles: Array = []
	if fl_on:
		poles = (game.upg.POLES as Array).duplicate()
		poles.sort_custom(func(a, b): return Vector2(a[0], a[1]).distance_squared_to(me) < Vector2(b[0], b[1]).distance_squared_to(me))
	for i in _floods.size():
		var d: Dictionary = _floods[i]
		if i < poles.size():
			d.at = Vector2(poles[i][0], poles[i][1] - 0.9)
			(d.p as AudioStreamPlayer2D).global_position = Vector2(d.at) * TILE
			d.want = 0.6
			d.db = -6.0
		else:
			d.want = 0.0
	var fl: Dictionary = _spot["flutter"]
	fl.want = (0.25 + 0.75 * _wind) * 0.7 if base_mode and game.phase == "managed" and night < 0.5 else 0.0
	fl.db = -5.0
	(fl.p as AudioStreamPlayer2D).global_position = LAUNDRY * TILE
	var rd: Dictionary = _spot["static"]
	rd.want = 0.6 if base_mode and game.phase == "managed" and game.econ != null and game.econ.tier("radio") >= 1 else 0.0
	rd.db = -6.0
	(rd.p as AudioStreamPlayer2D).global_position = RADIO * TILE


## ------------------------------------------------------------------------------ hearing

func _hearing(dt: float) -> void:
	var hp: float = s.hp
	var k := clampf(1.0 - hp / 0.3, 0.0, 1.0) if game.mode == "raid" or game.phase == "clear" else 0.0
	_deaf = maxf(0.0, _deaf - dt)
	k = maxf(k, clampf(_deaf / 2.0, 0.0, 1.0))
	_muffle = move_toward(_muffle, k, 1.5 * dt)
	var fx = AudioServer.get_bus_effect(0, 0) if AudioServer.get_bus_effect_count(0) > 0 else null
	if fx is AudioEffectLowPassFilter:
		fx.cutoff_hz = exp(lerpf(log(20500.0), log(2200.0), _muffle))
	if hp < 0.3 and hp > 0.0 and not get_tree().paused and (game.mode == "raid" or game.phase == "clear"):
		_heart_t -= dt
		if _heart_t <= 0.0:
			_heart_t = lerpf(0.55, 0.95, hp / 0.3)
			sfx("pu_heart_0", -6.0 + 4.0 * (1.0 - hp / 0.3), 1.0, "SFX")
	else:
		_heart_t = 0.0


## Hearing dulled for `secs` seconds (an explosion near her): the master's low-pass closes and opens again.
func deafen(secs: float) -> void:
	_deaf = maxf(_deaf, secs)


## ------------------------------------------------------------------------------ the rules' events

func on_event(e: Dictionary) -> void:
	if not enabled:
		return
	if _log:
		_note("event:" + String(e.type))
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	match String(e.type):
		"shot":
			_tail(e, me)
		"searched", "room_searched", "stash_open":
			_search()
		"picked":
			sfx("pu_pickup_%d" % _rng.randi_range(0, 1), -6.0, _rng.randf_range(0.95, 1.08), "SFX")
		"gate":
			_gate(e)
		"entered", "left":
			_door(int(e.get("house", -1)), String(e.type) == "entered")
		"claw":
			_claw(e, me)
		"bite":
			_bitten(e, me)
		"stab":
			if _rng.randf() < 0.3:
				bark("female", "effort", -5.0, null)
		"reload":
			if String(e.get("who", "")) == "" and _rng.randf() < 0.1:
				bark("female", "grunt", -9.0, null)
		"crash":
			deafen(0.0)


func _tail(e: Dictionary, me: Vector2) -> void:
	var d := me.distance_to(Vector2(float(e.x), float(e.y)))
	if d > 70.0:
		return
	var w := String(e.get("weapon", "")) + " " + String(e.get("gun", ""))
	var k := 1
	if w.contains("shot"):
		k = 2
	elif w.contains("pistol") or w.contains("revolver") or w.contains("handgun") or w.contains("glock"):
		k = 0
	var key := "pt_tail_%d" % k
	if _t - float(_last.get(key, -9.0)) < 0.12:
		return
	var delay := 0.06 + d * 0.0045
	var db := -9.0 - d * 0.28 - (3.0 if k == 0 else 0.0)
	_last[key] = _t
	get_tree().create_timer(delay, true, false, true).timeout.connect(func(): sfx(key, db, _rng.randf_range(0.94, 1.06), "SFX", 0.0))


func _search() -> void:
	var r := _rng.randi_range(0, 2)
	if r == 0:
		sfx("pu_lid_%d" % _rng.randi_range(0, 1), -6.0, _rng.randf_range(0.95, 1.05), "SFX")
	else:
		sfx("pu_rustle_%d" % _rng.randi_range(0, 1), -5.0, _rng.randf_range(0.95, 1.05), "SFX")
	if _rng.randf() < 0.25:
		get_tree().create_timer(0.5, true, false, true).timeout.connect(func(): sfx("pu_glass_0", -9.0, _rng.randf_range(0.95, 1.05), "SFX"))


func _gate(e: Dictionary) -> void:
	var st := String(e.get("state", ""))
	var at: Variant = null
	if e.has("x"):
		at = Vector2(float(e.x), float(e.y))
	sfx("pd_chain_0", -4.0, _rng.randf_range(0.95, 1.05), "SFX", 0.05, at, 30.0)
	if st == "open" or st == "opening" or st == "":
		get_tree().create_timer(0.4, true, false, true).timeout.connect(func(): sfx("pd_rolling_0", -4.0, 1.0, "SFX", 0.05, at, 30.0))


## A door of a building: a cell block's is a barred steel door (unlocked, then slammed behind her), any other a wooden one.
func _door(house: int, entering: bool) -> void:
	var cell := false
	if house >= 0 and game.town != null and house < (game.town.houses as Array).size():
		var r: Rect2i = game.town.houses[house].get("rect", Rect2i())
		var c := Vector2(r.get_center())
		if game.mode == "base":
			for z in game.base.ZONES:
				if (z.id == "cella" or z.id == "cellb") and Rect2(z.rect).has_point(c):
					cell = true
	if cell:
		sfx("pd_cell_open_0", -5.0, _rng.randf_range(0.96, 1.04), "SFX", 0.3)
		get_tree().create_timer(0.55, true, false, true).timeout.connect(func(): sfx("pd_cell_slam_%d" % _rng.randi_range(0, 1), -8.0, _rng.randf_range(0.95, 1.05), "SFX", 0.3))
	else:
		sfx("door_open_0", -5.0, _rng.randf_range(0.95, 1.05), "SFX", 0.3, null, 20.0, OLD)
		get_tree().create_timer(0.6, true, false, true).timeout.connect(func(): sfx("door_close_0", -7.0, _rng.randf_range(0.95, 1.05), "SFX", 0.3, null, 20.0, OLD))


## The prison gate (the truck goes out, the truck comes back): the chain, then the rolling door.
func gate_sound() -> void:
	sfx("pd_chain_0", -3.0, 1.0, "SFX", 0.5)
	get_tree().create_timer(0.5, true, false, true).timeout.connect(func(): sfx("pd_rolling_0", -3.0, 1.0, "SFX", 0.5))


func _claw(e: Dictionary, me: Vector2) -> void:
	var at := Vector2(float(e.x), float(e.y))
	if at.distance_to(me) > 22.0 or _t - float(_next.chain) < 0.9:
		return
	_next.chain = _t
	sfx("pd_chain_0", -14.0, _rng.randf_range(1.1, 1.35), "SFX", 0.0, at, 22.0)


func _bitten(e: Dictionary, me: Vector2) -> void:
	var who := String(e.get("who", ""))
	var at := Vector2(float(e.x), float(e.y))
	if who == String(game.run.avatar_p.id) or at.distance_to(me) < 1.5:
		bark("female", "pain", -3.0, null)
	elif at.distance_to(me) < 22.0:
		bark(_voice_of(who), "pain", -3.0, at)


func _voice_of(id: String) -> String:
	return VOICES[abs(id.hash()) % 3]


## A bark: a short vocal sound ("grunt", "gasp", "cough", "effort", "pain", "sob", "whistle") of a voice ("male", "female", "old"); rate limited: one in 0.9 s, one voice not twice in 3 s.
func bark(who: String, kind: String, db: float, at) -> void:
	if not enabled:
		return
	if _t - _bark_at < 0.9 or _t - float(_bark_who.get(who + kind, -9.0)) < 3.0:
		return
	_bark_at = _t
	_bark_who[who + kind] = _t
	sfx("pv_%s_%s" % [who, kind], db, _rng.randf_range(0.95, 1.05), "Voices", 0.0, at, 20.0)


func _watch_people(me: Vector2) -> void:
	# hurt: hp falls (Ruth, the crew, the allies)
	var ps: Array = [game.run.avatar_p]
	if game.crew != null:
		for m in game.crew.members:
			ps.append(m.p)
	for p in ps:
		var id := String(p.id)
		var hp := float(p.hp)
		var prev: float = _prev_hp.get(id, hp)
		_prev_hp[id] = hp
		var was_down: bool = _prev_down.get(id, false)
		_prev_down[id] = bool(p.downed)
		if prev - hp >= 3.0 and hp > 0.0 and id != String(game.run.avatar_p.id):
			var at := Vector2(p.x, p.y)
			if at.distance_to(me) < 22.0 and _rng.randf() < 0.6:
				bark(_voice_of(id), "pain" if prev - hp > 9.0 else "grunt", -3.0, at)
		elif id == String(game.run.avatar_p.id) and prev - hp >= 3.0 and hp > 0.0 and _rng.randf() < 0.7:
			bark("female", "pain" if prev - hp > 9.0 else "grunt", -3.0, null)
		elif p.downed and not was_down and id != String(game.run.avatar_p.id):
			bark(_voice_of(id), "pain", -2.0, Vector2(p.x, p.y))
		elif hp > prev + 25.0:
			bark(_voice_of(id), "gasp", -4.0, Vector2(p.x, p.y) if id != String(game.run.avatar_p.id) else null)


## ------------------------------------------------------------------------------ footsteps

func _steps(dt: float) -> void:
	if dt <= 0.0:
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	_step_one("ruth", me, dt, null, false)
	if game.crew != null:
		var near: Array = []
		for m in game.crew.members:
			if m.p == game.run.avatar_p:
				continue
			if Vector2(m.p.x, m.p.y).distance_squared_to(me) < 400.0:
				near.append(m)
		for m in near.slice(0, 8):
			_step_one(String(m.p.id), Vector2(m.p.x, m.p.y), dt, Vector2(m.p.x, m.p.y), false)
	# the dead: the nearest ones that are on the move
	var c := 0
	for z in game.run.sim.zombies:
		if z.state == "dying" or z.state == "dead" or not z.moving:
			continue
		var d2: float = (z.x - me.x) * (z.x - me.x) + (z.y - me.y) * (z.y - me.y)
		if d2 > 324.0:
			continue
		c += 1
		if c > 10:
			break
		_step_one("z%d" % z.get_instance_id(), Vector2(z.x, z.y), dt, Vector2(z.x, z.y), true)


func _step_one(id: String, pos: Vector2, dt: float, at, dead: bool) -> void:
	var prev: Vector2 = _prev_pos.get(id, pos)
	_prev_pos[id] = pos
	var moved := pos.distance_to(prev)
	if moved < 0.004 or moved > 2.0:
		return
	var acc: float = float(_stride.get(id, _rng.randf() * STRIDE)) + moved
	var speed := moved / maxf(dt, 0.001)
	var stride := STRIDE * (0.8 if dead else 1.0) * (1.25 if speed > 5.0 else 1.0)
	if acc < stride:
		_stride[id] = acc
		return
	_stride[id] = acc - stride
	var ground := _ground_at(pos.x, pos.y)
	if dead:
		var k := "pf_shuffle_%d" % _rng.randi_range(0, 3)
		if _rng.randf() < 0.18:
			k = "pf_drag_%d" % _rng.randi_range(0, 1)
		sfx(k, -2.0, _rng.randf_range(0.85, 1.15), Buses.category_bus("Steps"), 0.0, at, 16.0)
		return
	var run := speed > 5.0
	var db := -3.0 if id == "ruth" else -6.0
	if ground == "mud":
		sfx("pf_mud_%d" % _rng.randi_range(0, 3), db + 5.0, _rng.randf_range(0.9, 1.1), Buses.category_bus("Steps"), 0.0, at, 16.0)
		return
	var f := String(STEP_FILES.get(ground, "fs_pave"))
	var n := _rng.randi_range(0, 2)
	var key := ("%s_run_%d" % [f, _rng.randi_range(0, 1)]) if run else ("%s_%d" % [f, n])
	sfx(key, db, _rng.randf_range(0.93, 1.07), Buses.category_bus("Steps"), 0.0, at, 16.0, OLD)


## ------------------------------------------------------------------------------ the base's life

func _life(dt: float) -> void:
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var base_mode: bool = game.mode == "base" and game.phase == "managed"
	var night := float(s.night)
	if _t >= float(_next.moan):
		_next.moan = _t + _rng.randf_range(6.0, 16.0) * (1.6 - night)
		if game.mode == "base":
			var d := maxf(0.0, PEN.y - me.y - 4.0) + absf(PEN.x - me.x) * 0.2
			if d < 60.0:
				sfx("moan_far_%d" % _rng.randi_range(0, 1), -8.0 - d * 0.25, _rng.randf_range(0.85, 1.1), Buses.far_bus(), 0.0, null, 0.0, OLD)
	if _t >= float(_next.owl) and base_mode:
		_next.owl = _t + _rng.randf_range(30.0, 75.0)
		if night > 0.6:
			sfx("pa_owl_%d" % _rng.randi_range(0, 1), -7.0, _rng.randf_range(0.95, 1.05), "Outside")
	if _t >= float(_next.crow) and base_mode:
		_next.crow = _t + _rng.randf_range(20.0, 55.0)
		if night < 0.4 and _rain < 0.2:
			sfx("crow_%d" % _rng.randi_range(0, 2), -9.0, _rng.randf_range(0.9, 1.1), Buses.far_bus(), 0.0, null, 0.0, OLD)
	if base_mode and game.crew != null and game.crew._meal_window() >= 0 and _t >= float(_next.clatter):
		_next.clatter = _t + _rng.randf_range(1.6, 4.5)
		if me.distance_to(CANTEEN) < 28.0:
			sfx("pa_clatter_%d" % _rng.randi_range(0, 2), -5.0, _rng.randf_range(0.92, 1.08), "SFX", 0.0, CANTEEN + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-2, 2)), 26.0)
	if base_mode and _t >= float(_next.whistle):
		_next.whistle = _t + _rng.randf_range(50.0, 110.0)
		if night < 0.4 and game.crew != null and not game.crew.members.is_empty():
			var m: Dictionary = game.crew.members[_rng.randi() % game.crew.members.size()]
			if Vector2(m.p.x, m.p.y).distance_to(me) < 20.0:
				bark(_voice_of(String(m.p.id)), "whistle", -8.0, Vector2(m.p.x, m.p.y))
	if base_mode and _t >= float(_next.cough):
		_next.cough = _t + _rng.randf_range(45.0, 100.0)
		if night > 0.4:
			if me.distance_to(Vector2(26.0, 20.0)) < 22.0:
				bark("old", "cough", -7.0, Vector2(26.0, 20.0))


## ------------------------------------------------------------------------------ one-shots

## Plays `key` from assets/audio/prison (or `dir`): `at` null is heard at its own level (a sound of Ruth's or of the mix), a Vector2 in tiles is placed in the world and fades with the distance (`reach` tiles).
## `gap` is the least time between two of the same sound. At most MAX_STARTS_PER_SEC start in a second, and a full pool drops the sound (never steals: a voice that plays is not cut).
func sfx(key: String, db := 0.0, pitch := 1.0, bus := "SFX", gap := 0.03, at = null, reach := 20.0, dir := DIR) -> bool:
	if not enabled:
		return false
	if gap > 0.0 and _t - float(_last.get(key, -9.0)) < gap:
		return false
	var st := _stream(key, dir)
	if st == null:
		return false
	var now := _t
	while not _starts.is_empty() and now - float(_starts[0]) > 1.0:
		_starts.pop_front()
	if _starts.size() >= MAX_STARTS_PER_SEC:
		return false
	var bus_name := bus if AudioServer.get_bus_index(bus) >= 0 else "SFX"
	if at == null:
		for p in _pool:
			if not (p as AudioStreamPlayer).playing:
				p.bus = bus_name
				p.stream = st
				p.volume_db = db
				p.pitch_scale = pitch
				p.play()
				return _started_ok(key)
	else:
		var tile := Vector2(at)
		for q in _pool2:
			if not (q as AudioStreamPlayer2D).playing:
				q.bus = bus_name
				q.stream = st
				q.volume_db = db
				q.pitch_scale = pitch
				q.max_distance = reach * TILE
				q.attenuation = 1.8
				q.global_position = tile * TILE
				q.play()
				return _started_ok(key)
	return false


func _started_ok(key: String) -> bool:
	_last[key] = _t
	_starts.append(_t)
	_note(key)
	return true


## A sound a project makes while it is built: the saw, the drill (the hammer is the sound node's).
func build_blow(pose: String, at: Vector2) -> void:
	if not enabled:
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	if at.distance_to(me) > 22.0:
		return
	var r := _rng.randf()
	if pose == "garden":
		return
	if r < 0.2:
		sfx("pb_saw_0", -9.0, _rng.randf_range(0.95, 1.05), "SFX", 1.5, at, 20.0)
	elif r < 0.32:
		sfx("pb_drill_0", -10.0, _rng.randf_range(0.95, 1.05), "SFX", 2.5, at, 20.0)


## A project is finished (the econ's signal).
func project_done() -> void:
	sfx("pb_done_0", -8.0, 1.0, "UI", 0.5)


func ui_open() -> void:
	if game.sound != null:
		game.sound.ui("ui_open", 0.8)


func ui_close() -> void:
	if game.sound != null:
		game.sound.ui("ui_close", 0.8)


## --audiotour: every file of assets/audio/prison/ in turn (the loops and stems for 5 s, the rest once), the name printed as it starts. For listening to all of it in a few minutes.
func _tour_step(dt: float) -> void:
	_tour_t -= dt
	if _tour_t > 0.0:
		return
	if _tour_player == null:
		_tour_player = AudioStreamPlayer.new()
		add_child(_tour_player)
	var key: String = _tour.pop_front()
	var looped := key.begins_with("pm_") or key.begins_with("pa_rain") or key.begins_with("pa_wind") or key in ["pa_fire", "pa_buzz", "pa_room", "pa_flutter", "pa_static"]
	var st := _looped(key) if looped else _stream(key)
	_tour_player.stop()
	if st == null:
		return
	_tour_player.bus = "Music" if key.begins_with("pm_") else ("Ambience" if looped else "SFX")
	_tour_player.stream = st
	_tour_player.volume_db = 0.0
	_tour_player.play()
	_tour_t = 5.0 if looped else maxf(1.0, st.get_length() + 0.5)
	print("TOUR ", key, " ", snappedf(st.get_length(), 0.1), " s")
	if _tour.is_empty():
		print("TOUR end")


## ------------------------------------------------------------------------------ the log

func _note(key: String) -> void:
	if not _log:
		return
	_counts[key] = int(_counts.get(key, 0)) + 1
	if not key.begins_with("event:"):
		var sec := int(_t)
		_sec_counts[sec] = int(_sec_counts.get(sec, 0)) + 1
		print("AUDIO %.1f %s" % [_t, key])


func _log_frame() -> void:
	if int(_t / 5.0) != int((_t - get_process_delta_time()) / 5.0):
		var g := ""
		for n in _gain:
			if float(_gain[n]) > 0.01:
				g += "%s=%.2f " % [n, float(_gain[n])]
		print("AUDIOLOG t=%.0f mode=%s/%s h=%.1f night=%.2f threat=%.2f chase=%.2f exit=%.0f indoor=%.1f rain=%.2f duck=%.1f stems: %s" % [_t, s.mode, s.phase, s.tod, s.night, s.threat, s.chase, s.exit, _indoor, _rain, _duck, g])
	var n := int(game.args.get("frames", "0"))
	if n > 0 and game.frames >= n and not game.args.has("shot") and not game.args.has("perf"):
		_summary()
		get_tree().quit()


func _summary() -> void:
	var worst := 0
	for k in _sec_counts:
		worst = maxi(worst, int(_sec_counts[k]))
	print("AUDIOLOG seconds ", snappedf(_t, 0.1), " worst starts in one second ", worst)
	var keys := _counts.keys()
	keys.sort()
	for k in keys:
		print("AUDIOLOG count ", k, " ", _counts[k], " (", snappedf(float(_counts[k]) / maxf(_t / 60.0, 0.01), 0.1), " a minute)")
	for b in _peaks:
		print("AUDIOLOG peak ", b, " ", snappedf(float(_peaks[b]), 0.1), " dB")
	var g := ""
	for n in _gain:
		g += "%s=%.2f " % [n, float(_gain[n])]
	print("AUDIOLOG stems at the end ", g)
	print("AUDIOLOG mix state ", s)
