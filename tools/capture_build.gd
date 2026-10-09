extends "res://tools/capture_tap.gd"
## `--capture=build`: BUILDING BY HAND for a movie run (docs/audio-capture.md): after `--stage=claimed` she orders the front fence on the Build page (the rules' own `order_project("front")`),
## walks to its first section, presses E there and stays by it: the hammer rings every 0.6 s while her hands work, a section finishing is the small bell, and when it is done and another
## waits within reach she presses E again. (The staging flag `--hands=` stops the clock for its picture: no sound; this is the real session at the real pace.)

var _ordered := false
var _site := Vector2.INF
var _e_cool := 0.0
var _presses := 0


func _hands(dt: float) -> void:
	var sim = main.sim
	var me = sim.avatar.player()
	if me == null or not bool(sim.base.claimed):
		return
	_e_cool = maxf(_e_cool - dt, 0.0)
	if engage(dt, 12.0):
		walk_keys(Vector2.ZERO, false)    # (a straggler of the street: first the dead, then the fence)
		_path = []
		return
	if not _ordered:
		_ordered = true
		if not sim.perimeter.projects().is_empty():
			print("CAPTURE order: ", String(sim.perimeter.order_project("front").get("line", "")))
	if _site == Vector2.INF:
		for e in sim.build_hands.sites():
			var rect: Rect2i = e.rect
			var mid := Vector2(rect.position) + Vector2(rect.size) * 0.5
			var to_house: Vector2 = sim.base.center() - mid
			var dir := to_house.normalized() if to_house.length() > 0.1 else Vector2(0.0, -1.0)
			_site = (Vector2(clampf(mid.x, float(rect.position.x) + 0.5, float(rect.end.x) - 0.5), clampf(mid.y, float(rect.position.y) + 0.5, float(rect.end.y) - 0.5)) + dir * 1.3).floor() + Vector2(0.5, 0.5)
			print("CAPTURE site at ", _site, " (", String(e.slot), ")")
			break
		return
	if sim.uses.busy():
		walk_keys(Vector2.ZERO, false)
		return
	var d := walk_toward(_site, 0.45)
	if d != Vector2.ZERO:
		walk_keys(d, false)
		return
	walk_keys(Vector2.ZERO, false)
	if _e_cool <= 0.0:
		for c in sim.interact.candidates():
			if String(c.kind) == "build":
				tap_key(KEY_E)
				_presses += 1
				_e_cool = 1.5
				print("CAPTURE E pressed (%d) at frame %d" % [_presses, frame])
				break
