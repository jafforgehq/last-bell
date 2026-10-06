## Staging for the pictures of BUILDING BY HAND (One House, EARLY: scripts/town/build_hands.gd): a screenshot has no player, so `--hands=<mode>` puts her beside the front fence, ordered, and has her hold E at it.
## Only the flag turns any of it on; scripts/ui/tutor_cues.gd calls `on_frame` (a view part of the town, one call a frame). (Not `--build`: that opens the old Build screen.)
##
##   --hands=idle            the front fence ordered, the avatar a step from its first section: the E prompt as it is first seen ("Build the front fence (hold)", the pale ring)
##   --hands=hold[:F]        the session begun and F (0.5) of what it needs run: the ring filling on the prompt, the section's own progress
##   --hands=up              every section of the front fence finished at once: "The front fence is up", and the objective goes on to the survivors
##   --hands=done            run to the end (a little more): the section stands, and the next one in reach is begun (the front fence is up when the project is)
## Give it after `--stage=claimed` (the base is needed); it stops the clock itself so that the picture stays where it was staged. The rules are used as the rules are: the order is the Build page's
## (`perimeter.order_project`), the session is begun with `interact.use` and run with `uses.update` and `build_hands.update`.
extends RefCounted

static var _parsed := false
static var _mode := ""
static var _arg := -1.0
static var _placed := false
static var _acted := false


static func _parse() -> void:
	_parsed = true
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--hands="):
			var bits := a.trim_prefix("--hands=").split(":")
			_mode = bits[0]
			if bits.size() > 1 and bits[1].is_valid_float():
				_arg = float(bits[1])


## Called by tutor_cues.gd every frame.
static func on_frame(main) -> void:
	if not _parsed:
		_parse()
	if _mode == "":
		return
	var sim = main.get("sim")
	if sim == null or sim.get("build_hands") == null or sim.get("avatar") == null or sim.avatar.player() == null or not bool(sim.base.claimed):
		return
	var now: int = int(main.get("frame_count"))
	if now < 4:
		return
	main.speed = 0
	if not _placed and now >= 5:
		_placed = true
		_place(main, sim)
	if not _placed or _acted:
		return
	if (_mode == "hold" or _mode == "done") and now >= 8:
		_acted = true
		_run(sim, _mode == "done", _arg if _arg >= 0.0 else 0.5)
	elif _mode == "up" and now >= 8:
		# (the whole front fence up at once, by the Build module's own work: the alert "The front fence is up" and the objective's next line)
		_acted = true
		for e in sim.build_hands.sites():
			sim.build.hand_work(String(e.plot), 999.0)


static func _place(main, sim) -> void:
	var per = sim.perimeter
	if not per.projects().is_empty():
		var r: Dictionary = per.order_project("front")
		print("--hands: %s" % String(r.get("line", "")))
	var me = sim.avatar.player()
	var best := {}
	for e in sim.build_hands.sites():
		best = e
		break
	if best.is_empty():
		print("--hands: nothing is ordered (scrap %d)" % int(sim.stock.scrap))
		return
	var rect: Rect2i = best.rect
	var mid := Vector2(rect.position) + Vector2(rect.size) * 0.5
	var to_house: Vector2 = sim.base.center() - mid
	var dir := to_house.normalized() if to_house.length() > 0.1 else Vector2(0.0, -1.0)
	var at := (Vector2(clampf(mid.x, float(rect.position.x) + 0.5, float(rect.end.x) - 0.5), clampf(mid.y, float(rect.position.y) + 0.5, float(rect.end.y) - 0.5)) + dir * 1.3).floor() + Vector2(0.5, 0.5)
	me.x = at.x
	me.y = at.y
	me.path = []
	me.moving = false
	me.facing = "S" if dir.y < 0.0 else "N"
	main.cam_center = at
	main.cam_hold = 0.0
	print("--hands: the avatar at (%.1f, %.1f) beside %s" % [at.x, at.y, String(best.slot)])


static func _run(sim, to_end: bool, frac: float) -> void:
	var picked := {}
	for c in sim.interact.candidates():
		if String(c.kind) == "build":
			picked = c
	if picked.is_empty():
		print("--hands: no build candidate in reach")
		return
	var r: Dictionary = sim.interact.use(picked)
	if not bool(r.get("ok", false)):
		print("--hands: refused: %s" % String(r.get("why", "")))
		return
	var seconds := float(r.get("seconds", 10.0))
	var run_s := seconds + 1.0 if to_end else seconds * clampf(frac, 0.0, 0.99)
	var t := 0.0
	while t < run_s and sim.uses.busy():
		sim.uses.update(1.0 / 30.0)
		sim.build_hands.update(1.0 / 30.0)
		t += 1.0 / 30.0
