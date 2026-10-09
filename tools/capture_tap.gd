extends Node
## `--capture=tap` (and the base of `capture_walk.gd` and `capture_fight.gd`): the listening post of a MOVIE run (docs/audio-capture.md). Added by main.gd's `--capture=<name>`.
##
## What it does, once the game is ready (30 frames after the HUD and the shell are up):
##   - puts an AudioEffectCapture on the Master bus before the limiter (the sum of everything the game plays, pre) and after it (post: what reaches the speakers) and on SFX, Steps,
##     Voices, Ambience, Rain, Distant, Music and UI (what each bus carries at the end of its own effects: BEFORE its own fader, which `meta.csv` records), and writes what each hears, every
##     frame, to `<--capture-out=DIR>/<bus>.f32` (raw 32-bit float stereo, 48 kHz): the stems of the clip, for tools/audio_capture.py.
##   - writes `meta.csv` (frame, game hour, Ruth's tile, the ground under her feet, the dead awake within 20 tiles, the nearest, her magazine, and every bus's fader in dB).
##   - gives its subclasses the hands of a player (`key`, `tap_key`, `walk_toward`) and a `_hands(dt)` to override.
## Nothing here is part of the game: it exists only when a run is started with `--capture=`.
const Foley := preload("res://scripts/audio/foley.gd")

const BUSES := ["Master", "SFX", "Steps", "Voices", "Ambience", "Rain", "Distant", "Music", "UI"]
const FADED := ["SFX", "UI", "Ambience", "Music", "Distant", "Rain", "Steps", "Voices"]
const READY_WAIT := 30

var main
var frame := 0
var started := false
var out_dir := ""
var opts := {}
var _wait := 0
var _caps := {}
var _files := {}
var _meta: FileAccess
var _held := {}
var _release: Array = []
var _path: Array = []
var _path_i := 0
var _path_t := 0.0
var _path_goal := Vector2.INF
var shots := 0
var swings := 0
var _melee_cool := 0.0
var _reload_cool := 0.0
var _last_mag := -1


func _ready() -> void:
	process_priority = -100    # (before the game's own frame: the hands are given, then the game takes them)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--capture-out="):
			out_dir = String(a).trim_prefix("--capture-out=")
		elif String(a).begins_with("--capture-") and String(a).contains("="):
			var kv := String(a).trim_prefix("--capture-").split("=", true, 1)
			opts[kv[0]] = kv[1]    # (--capture-waves=N, --capture-route=NAME: the subclasses' own)


func _process(dt: float) -> void:
	if main == null or not main.load_ms.has("args_shell"):
		return
	if not started:
		_wait += 1
		if _wait < READY_WAIT:
			return
		started = true
		_begin()
	frame += 1
	main.shot_frames = 99999999    # (a staging such as `--moment=dawn` asks for a shot a second after its card is up, and the shot ends the run: not in a movie)
	for code in _release:
		key(code, false)
	_release.clear()
	_hands(dt)
	_calib()
	_read()
	_log()


func _begin() -> void:
	print("CAPTURE start: process frame %d, hour %.2f" % [Engine.get_process_frames(), float(main.sim.hour)])
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	var master := AudioServer.get_bus_index("Master")
	var pre := AudioEffectCapture.new()
	pre.buffer_length = 0.5
	AudioServer.add_bus_effect(master, pre, 0)
	var post := AudioEffectCapture.new()
	post.buffer_length = 0.5
	AudioServer.add_bus_effect(master, post)
	_caps["Master_pre"] = pre
	_caps["Master"] = post
	for b in BUSES:
		if b == "Master":
			continue
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			continue
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, cap)
		_caps[b] = cap
	if out_dir != "":
		for k in _caps.keys():
			_files[k] = FileAccess.open("%s/%s.f32" % [out_dir, k], FileAccess.WRITE)
		_meta = FileAccess.open(out_dir + "/meta.csv", FileAccess.WRITE)
		var head := "frame,hour,x,y,ground,dead20,nearest,mag,ammo,speed,run"
		for b in FADED:
			head += ",f_" + b
		_meta.store_line(head)
	# the buses' own faders, for the analysis (the stems are taken before them or after, see docs/audio-capture.md)
	var faders := {}
	for b in BUSES:
		var i2 := AudioServer.get_bus_index(b)
		if i2 >= 0:
			faders[b] = AudioServer.get_bus_volume_db(i2)
	print("CAPTURE faders: ", JSON.stringify(faders))


func _read() -> void:
	for k in _caps.keys():
		var cap: AudioEffectCapture = _caps[k]
		var n := cap.get_frames_available()
		if n <= 0:
			continue
		var buf: PackedVector2Array = cap.get_buffer(n)
		if _files.has(k) and _files[k] != null:
			_files[k].store_buffer(buf.to_byte_array())


func _log() -> void:
	if _meta == null:
		return
	var me = main.sim.avatar.player()
	if me == null:
		return
	var near := 999.0
	var n20 := 0
	for z in main.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var d := Vector2(me.x - z.x, me.y - z.y).length()
		if d < 20.0:
			n20 += 1
		near = minf(near, d)
	var ground := Foley.ground_at(main.get("world"), me.x, me.y)
	var run := int(bool(_held.get(KEY_X, false)))
	var faders := ""    # (every bus's fader now, dB: the stems are before them; the Ambience's has its duck and the Rain's its roof)
	for b in FADED:
		faders += ",%.2f" % AudioServer.get_bus_volume_db(AudioServer.get_bus_index(b))
	_meta.store_line("%d,%.3f,%.2f,%.2f,%s,%d,%.1f,%d,%d,%d,%d%s" % [frame, float(main.sim.hour), me.x, me.y, ground, n20, near, int(me.mag), int(main.sim.stock.ammo), int(main.speed), run, faders])
	if frame % 60 == 0:
		_meta.flush()
		for f in _files.values():
			if f != null:
				f.flush()


func _exit_tree() -> void:
	if _meta != null:
		_meta.flush()
	for f in _files.values():
		if f != null:
			f.flush()
	_files.clear()
	_meta = null


## `--capture-calib=groan`: the real window's check of docs/audio-mix.md's distances. A walker's groan (the soundscape's own `groan_play`, the voice the rules ask for) is played from 3, 3, 8,
## 14 and 3 tiles east of the camera, one every 3 seconds from the second second, and `calib.csv` says when (frame, tiles). tools/audio_capture.py `--calib` measures them on the Voices stem.
const CALIB_D := [3.0, 3.0, 8.0, 14.0, 3.0, 8.0]
var _calib_log: FileAccess


func _calib() -> void:
	if String(opts.get("calib", "")) != "groan" or out_dir == "":
		return
	var i := int((frame - 60) / 90)
	if frame < 60 or (frame - 60) % 90 != 0 or i >= CALIB_D.size():
		return
	if _calib_log == null:
		_calib_log = FileAccess.open(out_dir + "/calib.csv", FileAccess.WRITE)
		_calib_log.store_line("frame,tiles")
	var cam: Vector2 = main.cam_center
	var ok: bool = main.sound.scape.groan_play(cam + Vector2(CALIB_D[i], 0.0), "walker", false, cam)
	_calib_log.store_line("%d,%.1f" % [frame, CALIB_D[i]])
	_calib_log.flush()
	print("CAPTURE calib groan at %.0f tiles: played %s" % [CALIB_D[i], str(ok)])


## Override: the hands of this frame (keys, the pointer's tile, the trigger).
func _hands(_dt: float) -> void:
	pass


# ---------------------------------------------------------------------------- hands --

## A key held down (or let go), as the keyboard would say it (the game reads `Input.is_physical_key_pressed`).
func key(code: Key, on: bool) -> void:
	if bool(_held.get(code, false)) == on:
		return
	_held[code] = on
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = on
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## A key pressed now and let go at the start of the next frame (R, F, E...).
func tap_key(code: Key) -> void:
	key(code, true)
	_release.append(code)


## Ruth's hands in a fight: aim at the nearest of the dead that is awake within `within` tiles (the right button held and the pointer on it), pull the trigger while the magazine has a
## round, reload (R) when it is empty, and swing the gun's butt (F) at one at arm's length. True while there is such a one (the caller stands still then).
func engage(dt: float, within: float = 11.0, gun: bool = true) -> bool:
	var sim = main.sim
	var me = sim.avatar.player()
	_melee_cool = maxf(_melee_cool - dt, 0.0)
	_reload_cool = maxf(_reload_cool - dt, 0.0)
	var best = null
	var best_d := 1.0e9
	var from: Vector2 = sim.avatar.shoulder(me)
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "retreat":
			continue
		var d := Vector2(z.x - me.x, z.y - me.y).length()
		if d >= best_d or d > within:
			continue
		# a clear line (the first thing a shot meets is this one: not a wall, not another of the dead), else it is not worth a shell (an arm's length is, for the butt)
		var ang := (Vector2(z.x, z.y - 0.5) - from).angle()
		if d > float(sim.avatar.melee_reach()) + 0.3 and sim.avatar.trace(from, ang, d + 0.5).z != z:
			continue
		best_d = d
		best = z
	if _last_mag >= 0 and int(me.mag) < _last_mag:
		shots += 1
	_last_mag = int(me.mag)
	if int(me.mag) <= 0 and _reload_cool <= 0.0 and float(me.reloading) <= 0.0 and (best != null and best_d < within + 6.0):
		tap_key(KEY_R)
		_reload_cool = 0.8
	if best == null or best_d > within:
		main.shot_aim = Vector2.INF
		main.shot_aiming = false
		main.aim_held = false
		main.firing = false
		return false
	main.shot_aim = Vector2(best.x, best.y - 0.5)
	main.shot_aiming = true
	main.aim_held = true
	main.firing = gun and int(me.mag) > 0
	if best_d < float(sim.avatar.melee_reach()) + 0.3 and _melee_cool <= 0.0:
		tap_key(KEY_F)
		_melee_cool = 0.9
		swings += 1
	return true


## The walk keys for a direction (W A S D: eight ways) and the run key.
func walk_keys(d: Vector2, run: bool) -> void:
	key(KEY_D, d.x > 0.38)
	key(KEY_A, d.x < -0.38)
	key(KEY_S, d.y > 0.38)
	key(KEY_W, d.y < -0.38)
	key(KEY_X, run and d != Vector2.ZERO)


## The direction to walk toward `dest` along the people's grid (ZERO within `arrive` tiles).
func walk_toward(dest: Vector2, arrive: float = 0.6) -> Vector2:
	var me = main.sim.avatar.player()
	var pos := Vector2(me.x, me.y)
	if pos.distance_to(dest) <= arrive:
		return Vector2.ZERO
	_path_t -= get_process_delta_time()
	if _path.is_empty() or _path_goal.distance_to(dest) > 0.5 or _path_t <= 0.0:
		_path = main.sim.path_p.find(main.sim.world.solid_p, pos.x, pos.y, dest.x, dest.y)
		if _path.is_empty():
			_path = [dest]
		_path_i = 0
		_path_goal = dest
		_path_t = 0.4
	while _path_i < _path.size() - 1 and pos.distance_to(Vector2(_path[_path_i])) < 0.5:
		_path_i += 1
	var wp := Vector2(_path[mini(_path_i, _path.size() - 1)])
	return (wp - pos).normalized()
