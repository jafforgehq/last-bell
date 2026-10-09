## The patrol's film (PATROL4): plays a real night of the real game in a window and saves a frame every few seconds of game time, to be set side by side (tools/patrol_sheet.py) and LOOKED AT:
## jitter, people standing in the open, people clumped, nobody covering a side, someone outside the lot, shots with no target. The game's own `_process` is driven by this script at a
## fixed frame time (so a run is the same on a busy machine), the speed is pressed with the game's own keys (Shift+1 and Shift+3 in an avatar game) and the call to arms with L.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . --script res://tools/patrol_film.gd -- --town=1 --stage=night --slots=built --winpx=1280x800 --os-scale=1 --prefs=user://prefs_shot.cfg \
##        --film=/path/dir [--every=8] [--secs=380] [--fspeed=1] [--fps=30] [--zoom=20] [--people=3] [--fall-at=120] [--marks=1] [--hud=0] [--call=0]
##
##   --film=DIR       where the frames go: f000.png, f001.png ... and film.log (one line of the crew's places and modes for each frame)
##   --every=8        seconds of game time between frames
##   --secs=380       how long the film is (game seconds from the first frame): a night from the bell to dawn is about 350
##   --fspeed=1       the game's speed key (1 or 3)
##   --fps=30         the frame rate the script plays at (every frame is one `_process` of the game)
##   --zoom=20        pixels to the tile (the camera is held on the base's lot)
##   --people=3       the crew besides the avatar (the stage has two, the rest are made up at her side)
##   --fall-at=S      S seconds into the film a fence section falls (the one the dead claw at, else the nearest to them)
##   --marks=1        draws the patrol's own notes over the picture: the lot, the loop, a ring for each patroller coloured by what they do (white walk, blue pause, yellow go, orange hold, red engaged)
##   --hud=0          hides the HUD (default hidden)
##   --call=1         presses L (the call to arms) first
## The arguments the game takes (--town=N --stage=night --slots=built --weather-first-night=storm ...) are the game's.
extends SceneTree

const TILE := 64.0

var _main
var _marks: Node2D
var _show_marks := true
var _ring := {}


class Marks:
	extends Node2D
	var film


	func _draw() -> void:
		film.draw_marks(self)


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--%s=" % name):
			return String(a).trim_prefix("--%s=" % name)
	return default


func _initialize() -> void:
	_run.call_deferred()


func _key(code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		ev.shift_pressed = shift
		_main._unhandled_input(ev)


func _run() -> void:
	var out := _arg("film", "")
	var every := float(_arg("every", "8"))
	var secs := float(_arg("secs", "380"))
	var fspeed := int(_arg("fspeed", "1"))
	var fps := float(_arg("fps", "30"))
	var zoom := float(_arg("zoom", "20"))
	var people := int(_arg("people", "3"))
	var fall_at := float(_arg("fall-at", "-1"))
	_show_marks = _arg("marks", "1") != "0"
	var show_hud := _arg("hud", "0") != "0"
	if out == "":
		print("PATROL_FILM: give --film=DIR")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	# (the town is made over a number of frames behind a loading card: the game turns its own `_process` back on when `_ready` is done)
	var waited := 0
	while (not _main.is_processing() or _main.get("sim") == null) and waited < 4000:
		await process_frame
		waited += 1
	for i in 10:
		await process_frame
	var sim = _main.sim
	if sim == null or sim.get("patrol") == null:
		print("PATROL_FILM: not a town run (give --town=N --stage=night)")
		quit(1)
		return
	_main.set_process(false)
	var guard := 0
	var crew := 0
	while guard < 8:
		crew = 0
		for p in sim.people:
			if not p.player and not (p.dead or p.turned):
				crew += 1
		if crew >= people:
			break
		sim.scenario._stage_join(1)
		guard += 1
	var pat = sim.patrol
	pat.points()
	var lot: Rect2 = pat.lot()
	_main.hud.visible = show_hud
	if _main.hints != null:
		_main.hints.queue_free()    # (the tips' card would sit in the middle of the picture)
		_main.hints = null
	_main.follow = null
	_main.cam_hold = 1.0e12
	_main.cam_glide_s = 0.0
	_main.zoom_px = zoom
	_main.cam_center = lot.get_center()
	_main._clamp_camera()
	_main._apply_camera()
	if _show_marks:
		# (above the night's darkness: a layer of its own that follows the camera)
		var layer := CanvasLayer.new()
		layer.layer = 90
		layer.follow_viewport_enabled = true
		_main.add_child(layer)
		_marks = Marks.new()
		_marks.film = self
		layer.add_child(_marks)
	if _arg("call", "0") == "1":
		_key(KEY_L)
	_key(KEY_3 if fspeed == 3 else KEY_1, true)
	print("PATROL_FILM speed %d, %d crew, lot %s, camera %s zoom %.0f, first frame at game %.1f h" % [int(_main.speed), crew, str(lot), str(_main.cam_center), float(_main.zoom_px), float(sim.hour)])
	var dt := 1.0 / fps
	var per: int = maxi(1, roundi(every / (dt * float(maxi(_main.speed, 1)))))
	var frames := int(secs / every) + 1
	var log_lines: Array = []
	var t0: float = float(sim.t)
	var fell := false
	for k in frames:
		for i in per:
			_main._process(dt)
			if not fell and fall_at >= 0.0 and float(sim.t) - t0 >= fall_at:
				fell = _fall(sim, lot)
		_main.cam_center = lot.get_center()
		_main._apply_camera()
		if _marks != null:
			_marks.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var name := "%s/f%03d.png" % [out, k]
		img.save_png(name)
		log_lines.append(_line(sim, pat, k))
		if sim.over != "":
			print("PATROL_FILM: the run is over (%s) at frame %d" % [String(sim.over), k])
			break
	var f := FileAccess.open(out + "/film.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
	print("PATROL_FILM done: %d frames in %s" % [log_lines.size(), out])
	for l in log_lines:
		print(l)
	quit(0)


func _fall(sim, lot: Rect2) -> bool:
	var best = null
	var best_n := 0
	for seg in sim.segments:
		if int(seg.id) >= 100 or String(seg.kind) == "door" or int(seg.state) == 3:
			continue
		var n := 0
		for z in sim.zombies:
			if (z.state == "attack" or z.state == "breach") and Vector2(z.x, z.y).distance_to(seg.center) < 5.0:
				n += 1
		if n > best_n:
			best_n = n
			best = seg
	if best == null:
		# (nobody is clawing a section yet, or only the barred door: the section nearest to the first of the dead that come)
		var zbest = null
		var zd := 1.0e9
		for z in sim.zombies:
			if z.state == "approach" or z.state == "attack" or z.state == "chase":
				var d := Vector2(z.x, z.y).distance_to(lot.get_center())
				if d < zd:
					zd = d
					zbest = z
		if zbest == null:
			return false
		var bd := 1.0e9
		for seg in sim.segments:
			if int(seg.id) >= 100 or String(seg.kind) == "door" or int(seg.state) == 3:
				continue
			var d2: float = Vector2(zbest.x, zbest.y).distance_to(seg.center)
			if d2 < bd:
				bd = d2
				best = seg
		if best == null:
			return false
	best.hp = 0.0
	sim._segment_state(best)
	print("PATROL_FILM: %s falls at game %.1f s" % [String(best.name), float(sim.t)])
	return true


func _line(sim, pat, k: int) -> String:
	var parts: Array = []
	var dead := 0
	var claw := 0
	for z in sim.zombies:
		if z.state == "attack" or z.state == "breach":
			claw += 1
		if z.state == "attack" or z.state == "breach" or z.state == "approach":
			dead += 1
	var snap: Dictionary = {}
	for e in pat.snapshot():
		snap[String(e.id)] = e
	for p in sim.people:
		if p.dead or p.turned:
			continue
		var e = snap.get(String(p.id))
		var mode: String = String(e.mode) if e != null else ("-[%s]" % String(p.activity))
		parts.append("%s(%.1f,%.1f) %s%s" % [String(p.first).left(3), p.x, p.y, mode, " T" if p.target != null else ""])
	return "f%03d t=%6.1f h%5.2f %s dead %2d claw %2d | %s" % [k, float(sim.t), float(sim.hour), String(sim.phase), dead, claw, " | ".join(parts)]


## The notes drawn over the picture (the node is in the world, so the tile is 64 units).
func draw_marks(c: Node2D) -> void:
	if _main == null:
		return
	var sim = _main.sim
	var pat = sim.patrol
	var lot: Rect2 = pat.lot()
	c.draw_rect(Rect2(lot.position * TILE, lot.size * TILE), Color(1, 1, 1, 0.9), false, 4.0)
	var pts: Array = pat.points()
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		c.draw_line(a * TILE, b * TILE, Color(0.4, 1.0, 0.5, 0.8), 3.0)
		c.draw_circle(a * TILE, 5.0, Color(0.4, 1.0, 0.5, 0.9))
	var snap: Dictionary = {}
	for e in pat.snapshot():
		snap[String(e.id)] = e
	var font := ThemeDB.fallback_font
	for p in sim.people:
		if p.dead or p.turned or p.away != null:
			continue
		var at: Vector2 = Vector2(_main.view_pos(p)) * TILE
		var e = snap.get(String(p.id))
		var mode := "post" if e == null else String(e.mode)
		var col := Color(1, 1, 1, 0.9)
		match mode:
			"pause":
				col = Color(0.4, 0.7, 1.0, 0.95)
			"go":
				col = Color(1.0, 0.9, 0.2, 0.95)
			"hold":
				col = Color(1.0, 0.55, 0.1, 0.95)
			"engaged":
				col = Color(1.0, 0.2, 0.2, 0.95)
			"back":
				col = Color(1.0, 0.2, 1.0, 0.95)
			"post":
				col = Color(0.6, 0.6, 0.6, 0.9)
		c.draw_arc(at + Vector2(0, 8), 20.0, 0.0, TAU, 24, col, 3.0)
		c.draw_string(font, at + Vector2(-20, 42), "%s %s" % [String(p.first).left(3), mode], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, col)
	for z in sim.zombies:
		if z.state == "attack" or z.state == "breach":
			c.draw_circle(Vector2(z.x, z.y) * TILE + Vector2(0, 8), 7.0, Color(1.0, 0.1, 0.1, 0.7))
		elif z.state == "approach" or z.state == "chase":
			c.draw_circle(Vector2(z.x, z.y) * TILE + Vector2(0, 8), 5.0, Color(1.0, 0.6, 0.1, 0.55))
