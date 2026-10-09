## Staging for the pictures of SALVAGE (scripts/render/salvage_marks.gd): a screenshot has no player, so `--salvage=<kind>` puts her beside a piece of that kind. Only the flag turns any of it on.
##
##   --salvage=<kind>                 the avatar stands beside the nearest piece of that kind (a kind of assets/data/salvage.json: sofa, bed_single, fridge, car_h...) in a house that is not the
##                                    base's (its dead taken out, its rooms looked into, so that the house is clear), or in the street for a car: the E prompt as it is first seen
##   --salvage=<kind>:hold[:F]        the strip begun and F (0.5) of its seconds run: the ring on the prompt
##   --salvage=<kind>:done[:K]        run to the end K (14) frames before the shot: the rubble where it stood and the "+3 scrap" pop on its way to the stores
##   --salvage=<kind>:after           stripped at once, early: the rubble alone
## Give it after `--stage=claimed` (a base is needed for the other houses to be strippable) with `--speed=0`; it stops the clock itself so that the picture stays where it was staged.
## The rules are used as the rules are (the session is begun with `uses.use` and run with `uses.update`); the only things made up are the dead taken out of the house (`field.remove_record`,
## as `--stage=cleared` does) and the rooms opened (`clearing.reveal`).
extends RefCounted

static var _parsed := false
static var _kind := ""
static var _mode := "idle"
static var _arg := -1.0
static var _placed := false
static var _acted := false
static var _id := ""


static func _parse() -> void:
	_parsed = true
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--salvage="):
			var bits := a.trim_prefix("--salvage=").split(":")
			_kind = bits[0]
			if bits.size() > 1:
				_mode = bits[1]
			if bits.size() > 2 and bits[2].is_valid_float():
				_arg = float(bits[2])


## Called by salvage_marks.gd every frame with the frame's number.
static func on_frame(main, frame: int) -> void:
	if not _parsed:
		_parse()
	if _kind == "":
		return
	var sim = main.get("sim")
	if sim == null or sim.get("salvage") == null or sim.get("avatar") == null or sim.avatar.player() == null:
		return
	var shot := String(main.get("shot_path")) != ""
	var last: int = int(main.get("shot_frames")) if shot else 600
	var now: int = int(main.get("frame_count")) if shot else frame
	if now < 4:
		return
	main.speed = 0
	if not _placed and now >= 5:
		_placed = true
		_place(main, sim)
	if not _placed or _id == "" or _acted:
		return
	match _mode:
		"hold":
			if now >= 8:
				_acted = true
				_begin(sim, true, _arg if _arg >= 0.0 else 0.5)
		"done":
			var k: int = int(_arg) if _arg >= 0.0 else 14
			if now >= last - k:
				_acted = true
				_begin(sim, true, 9.0)
		"after":
			if now >= 8:
				_acted = true
				_begin(sim, true, 9.0)


## The avatar beside the nearest piece of the kind (and the house of it cleared).
static func _place(main, sim) -> void:
	var salv = sim.salvage
	var me = sim.avatar.player()
	var here := Vector2(me.x, me.y)
	var best := ""
	var best_d := INF
	for id in salv.pieces_of_kind(_kind):
		var pc: Dictionary = salv.piece(id)
		var h := int(pc.house)
		if (h >= 0 and salv.house_why_not(h) == "That is your home") or (h < 0 and salv.why_not(pc) == "That is your home"):
			continue
		var d := Vector2(pc.cx, pc.cy).distance_to(here)
		if d < best_d:
			best_d = d
			best = String(id)
	if best == "":
		print("--salvage: no piece of kind '%s' that can be stripped (kinds of assets/data/salvage.json)" % _kind)
		return
	var pc2: Dictionary = salv.piece(best)
	var h2 := int(pc2.house)
	var stand := _stand_tile(sim, pc2)
	me.x = stand.x
	me.y = stand.y
	me.path = []
	me.moving = false
	me.facing = "N"
	var cam = main.get("cam_center")
	if cam is Vector2:
		main.cam_center = stand
	if h2 >= 0:
		_clear_house(sim, h2)
	_id = best
	print("--salvage: %s %s in house %d at (%.1f, %.1f), the avatar at (%.1f, %.1f)" % [_kind, best, h2, float(pc2.cx), float(pc2.cy), stand.x, stand.y])


## A free tile beside the piece (the south side first, where she faces it), in its house (or in the street for a street piece).
static func _stand_tile(sim, pc: Dictionary) -> Vector2:
	var world = sim.world
	var W: int = world.W
	var rect: Rect2i = pc.rect
	var cands: Array = []
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			if rect.has_point(Vector2i(x, y)):
				continue
			if x < 0 or y < 0 or x >= W or y >= world.H:
				continue
			var at := Vector2(float(x) + 0.5, float(y) + 0.5)
			if int(world.solid_p[y * W + x]) != 0 or int(sim.houses.house_at(at.x, at.y)) != int(pc.house):
				continue
			var south := 0 if y >= rect.end.y and x >= rect.position.x and x < rect.end.x else 1
			cands.append([south, absf(at.x - float(pc.cx)), at])
	cands.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return cands[0][2] if not cands.is_empty() else Vector2(float(pc.cx), float(pc.cy) + 1.2)


## The dead taken out of the house, every room looked into, the clearing module given its look: the house is clear.
static func _clear_house(sim, h: int) -> void:
	var field = sim.get("field")
	var clearing = sim.get("clearing")
	if field == null or clearing == null:
		return
	for i in field.n:
		if int(field.status[i]) == 2:
			continue
		var tx := floori(field.xs[i])
		var ty := floori(field.ys[i])
		if int(field.tile_house[ty * field.W + tx]) == h:
			field.remove_record(i)
	for r in sim.houses.rooms_of(h):
		clearing.reveal(int(r), "stage")
	clearing.scan()
	clearing.scan()


## E at the piece: the session begun and run `frac` of it (a number over 1: to the end and a little more).
static func _begin(sim, _press: bool, frac: float) -> void:
	var uses = sim.uses
	var salv = sim.salvage
	# (SCAV3: a car of the street is searched before it is stripped: the staging has it searched, so that the strip's pictures are still made)
	var cid := String(salv.piece(_id).get("container", ""))
	if cid.begins_with("car") and not sim.search.is_looted(cid):
		sim.search.mark_looted(cid)
	var picked := {}
	for c in sim.interact.candidates():
		if String(c.kind) == "strip" and String(c.id) == _id:
			picked = c
	if picked.is_empty():
		print("--salvage: no strip candidate at the piece (%s)" % salv.why_not(salv.piece(_id)))
		return
	var r: Dictionary = sim.interact.use(picked)
	if not bool(r.get("ok", false)):
		print("--salvage: refused: %s" % String(r.get("why", "")))
		return
	var of := float(uses.progress().get("of", 8.0))
	var seconds := of + 0.5 if frac > 1.0 else of * clampf(frac, 0.0, 0.99)
	var t := 0.0
	while t < seconds and uses.busy():
		uses.update(1.0 / 30.0)
		t += 1.0 / 30.0
