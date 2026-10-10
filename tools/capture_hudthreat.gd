extends "res://tools/capture_fight.gd"
## `--capture=hudthreat` (HUD8): SIX FRAMES of the threat rule in a real window, one picture each, `--capture-out=DIR`: the quiet before, the dead in sight (the boards collapse), the fight, the
## last of them down, a second and a half after, and the quiet back (the boards return, one after the other, with a fade). Pair it with a staged day, `--stage=rescued2 --hour=11 --weapon=shotgun`,
## and `--winpx=WxH --os-scale=1`; it plays at the game's own pace and writes DIR/f1.png to f6.png and DIR/frames.txt (the time of each, and what the stage part said).
##   --capture-n=N   how many walkers (3)
const WALKERS := 3
## Game seconds from the start of the run to the wave; and the frames' times from the wave (first), from the last one down (the rest).
const WAVE_AT := 2.5
const SHOT_AT := {"f1": -0.3, "f2": 0.9, "f3": 3.5}

var _t := 0.0
var _wave_made := false
var _since_wave := 0.0
var _clear_t := -1.0
var _taken := {}
var _lines: PackedStringArray = PackedStringArray()


func _begin() -> void:
	if out_dir == "":
		out_dir = "/tmp/hudthreat"
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("HUDTHREAT start: window %s" % str(get_window().size))


func _read() -> void:
	pass


func _log() -> void:
	pass


func _calib() -> void:
	pass


func _exit_tree() -> void:
	pass


func _hands(dt: float) -> void:
	var sim = main.sim
	var me = sim.avatar.player()
	if me == null:
		return
	main.cam_hold = 0.0
	_t += dt
	if not _wave_made and _t >= WAVE_AT - 0.3 and not _taken.has("f1"):
		_snap("f1")
	if not _wave_made and _t >= WAVE_AT:
		_wave_made = true
		_since_wave = 0.0
		var n := int(opts.get("n", WALKERS))
		main.stage_fight("%d,walker,%.1f,%.1f,3.0" % [n, me.x + 2.0, me.y + 12.0])
		print("HUDTHREAT wave of %d at %.1f" % [n, _t])
	if not _wave_made:
		return
	_since_wave += dt
	var awake := 0
	for z in sim.zombies:
		if z.state != "dying" and z.state != "dead" and z.state != "retreat" and not bool(z.remove):
			awake += 1
	if engage(dt, 22.0, true):
		walk_keys(Vector2.ZERO, false)
	if not _taken.has("f2") and _since_wave >= float(SHOT_AT.f2):
		_snap("f2")
	if not _taken.has("f3") and _since_wave >= float(SHOT_AT.f3):
		_snap("f3")
	if _clear_t < 0.0 and awake == 0 and _since_wave > 2.0:
		_clear_t = 0.0
		print("HUDTHREAT the last one is down at wave +%.1f" % _since_wave)
	if _clear_t >= 0.0:
		_clear_t += dt
		if not _taken.has("f4") and _clear_t >= 0.4:
			_snap("f4")
		if not _taken.has("f5") and _clear_t >= 4.4:
			_snap("f5")
		if not _taken.has("f6") and _clear_t >= 7.5:
			await _snap("f6")
			var f := FileAccess.open(out_dir + "/frames.txt", FileAccess.WRITE)
			f.store_string("\n".join(_lines))
			f.close()
			get_tree().quit()
	if _since_wave > 60.0:
		print("HUDTHREAT gave up")
		get_tree().quit()


## One picture of the frame as it is, and a line of what the stage part says.
func _snap(tag: String) -> void:
	_taken[tag] = true
	var st = main.town.part("hud_stage")
	var line := "%s: run %.1f s, fight %s, calm %.1f s, forms clock=%s crew=%s objective=%s toolbar=%s alerts=%s, alpha clock %.2f crew %.2f objective %.2f toolbar %.2f" % [
		tag, _t, str(st.threat.on), st.threat.calm_for, st.form("clock"), st.form("crew"), st.form("objective"), st.form("toolbar"), st.form("alerts"),
		float(st.alpha.get("clock", 1.0)), float(st.alpha.get("crew", 1.0)), float(st.alpha.get("objective", 1.0)), float(st.alpha.get("toolbar", 1.0))]
	_lines.append(line)
	print("HUDTHREAT ", line)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, tag])
