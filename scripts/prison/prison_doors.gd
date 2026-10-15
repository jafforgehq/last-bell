## DOORS: a door in every doorway of the prison's buildings. In the clear phase they all start shut (solid for people and for the dead, so also for sight, shots and, through the wall count, for noise; the zone
## rule of the dormant dead already keeps a shut room's sleepers from hearing the next room) and E opens or shuts the one beside Ruth. The dead cannot open them. When the prison is secured the base is built
## again and every door is open for good (only drawn, no tile shut).
extends RefCounted

const Base := preload("res://scripts/prison/prison_base.gd")
const REACH := 1.7    # tiles from the doorway at which E answers
const DUR := 0.25    # seconds a door takes to swing open or shut
const STAGGER := 0.06    # seconds between the doors of the all-open event

var game
var open: Array = []    # bool per Base.DOORS
var _from: Array = []    # float per door: how open it was drawn when it last started to move
var _t0: Array = []    # int per door: the msec at which that move started


func setup(g, clear: bool) -> void:
	game = g
	open.resize(Base.DOORS.size())
	open.fill(not clear)
	_from.resize(open.size())
	_from.fill(0.0 if clear else 1.0)
	_t0.resize(open.size())
	_t0.fill(-100000)
	if clear:
		for i in open.size():
			_apply(i)


func _apply(i: int) -> void:
	var w = game.world
	var sim = game.run.sim
	var shut := 0 if bool(open[i]) else 1
	var r: Rect2i = Base.DOORS[i].rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var k: int = y * w.W + x
			w.solid_p[k] = shut
			w.solid_z[k] = shut
			sim.path_p.set_solid(k, shut == 1)
			sim.path_z.set_solid(k, shut == 1)
	sim._regions_dirty = true


func _dist(i: int, p: Vector2) -> float:
	var r := Rect2(Base.DOORS[i].rect)
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)).distance_to(p)


## The prompt of the nearest door in reach ({} when none).
func prompt(me: Vector2) -> Dictionary:
	var best := -1
	var bd := REACH
	for i in open.size():
		var d := _dist(i, me)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return {}
	return {"kind": "door", "i": best, "label": "E: %s door (%s)" % ["close" if bool(open[best]) else "open", String(Base.DOORS[best].name)]}


## Whoever stands in the doorway (Ruth, the crew, a dead one) keeps it from shutting.
func _blocked(i: int) -> bool:
	var r := Rect2(Base.DOORS[i].rect).grow(0.4)
	if r.has_point(Vector2(game.run.avatar_p.x, game.run.avatar_p.y)):
		return true
	for m in game.crew.members:
		if r.has_point(Vector2(m.p.x, m.p.y)):
			return true
	for z in game.run.sim.zombies:
		if z.state != "dead" and z.state != "dying" and r.has_point(Vector2(z.x, z.y)):
			return true
	return false


## Opens or shuts door i; returns the line to say.
func toggle(i: int) -> String:
	if bool(open[i]) and _blocked(i):
		return "Something is in the doorway."
	var cur := _k(i)
	open[i] = not bool(open[i])
	_apply(i)
	_swing(i, cur)
	return "Door open." if bool(open[i]) else "Door shut."


## The bot's way: a path as if every door were open (the walker then meets a door on it and opens it, `bot_open`).
func path(from: Vector2, to: Vector2) -> Array:
	var shut: Array = []
	for i in open.size():
		if not bool(open[i]):
			shut.append(i)
			_grid(i, false)
	var r: Array = game.run.sim.path_p.find(game.world.solid_p, from.x, from.y, to.x, to.y)
	for i in shut:
		_grid(i, true)
	return r


func _grid(i: int, solid: bool) -> void:
	var r: Rect2i = Base.DOORS[i].rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.run.sim.path_p.grid.set_point_solid(Vector2i(x, y), solid)


func bot_open(me: Vector2) -> void:
	for i in open.size():
		if not bool(open[i]) and _dist(i, me) < 1.4:
			toggle(i)


## How far a door is open, 0 (shut) to 1 (open), eased: it moves for DUR seconds after `_swing` (a stagger can delay the start).
func _k(i: int) -> float:
	var f := clampf(float(Time.get_ticks_msec() - int(_t0[i])) / (DUR * 1000.0), 0.0, 1.0)
	return lerpf(float(_from[i]), 1.0 if bool(open[i]) else 0.0, f)


## Starts the swing of door i to its new state (from wherever it is now), `delay` seconds from now, with its sound.
func _swing(i: int, cur: float, delay: float = 0.0) -> void:
	_from[i] = cur
	_t0[i] = Time.get_ticks_msec() + int(delay * 1000.0)
	if delay <= 0.0:
		_sound(i)
	elif is_instance_valid(game) and game.is_inside_tree():
		game.get_tree().create_timer(delay).timeout.connect(_sound.bind(i))


## A short sound at the door, wood for a plain door and steel for a cell block's.
func _sound(i: int) -> void:
	if not is_instance_valid(game) or game.audio == null:
		return
	var at := Rect2(Base.DOORS[i].rect).get_center()
	var o := bool(open[i])
	var cell := String(Base.DOORS[i].name) == "Cell block"
	var rng := randf_range(0.95, 1.05)
	if cell:
		game.audio.sfx("pd_cell_open_0" if o else "pd_cell_slam_0", -6.0, rng, "SFX", 0.05, at, 24.0)
	else:
		game.audio.sfx("door_open_0" if o else "door_close_0", -5.0, rng, "SFX", 0.05, at, 24.0, game.audio.OLD)


## The all-open event after the last zone: every shut door swings open one after the other (about 0.06 s apart). Returns how long the whole thing takes, in seconds.
func open_all() -> float:
	var n := 0
	for i in open.size():
		if not bool(open[i]):
			var cur := _k(i)
			open[i] = true
			_apply(i)
			_swing(i, cur, float(n) * STAGGER)
			n += 1
	return DUR + float(maxi(n - 1, 0)) * STAGGER if n > 0 else 0.0


func paint(c: CanvasItem) -> void:
	for i in open.size():
		_paint_door(c, i, _k(i))


## One door at progress k. A door is drawn as its face (planks, a handle) seen from the south: opening swings it about its hinge end, so the face is squeezed toward the hinge until only the
## leaf's edge shows (5 px, the old open drawing), and the jambs and the dark threshold come in as it goes.
func _paint_door(c: CanvasItem, i: int, k: float) -> void:
	var t: float = game.TILE
	var edge := Color(0.07, 0.06, 0.05)
	var e := k * k * (3.0 - 2.0 * k)
	var r := Rect2(Base.DOORS[i].rect)
	var px := Rect2(r.position * t, r.size * t)
	var horiz := r.size.x >= r.size.y
	var full: float = px.size.x if horiz else px.size.y    # the doorway's length
	var depth: float = px.size.y if horiz else px.size.x
	var w := lerpf(full, 5.0, e)    # the leaf's length along the doorway
	var off := lerpf(0.0, -2.0, e)
	var leaf := Rect2(px.position + (Vector2(0, off) if horiz else Vector2(off, 0)), Vector2(w, depth) if horiz else Vector2(depth, w))
	if e > 0.0:
		c.draw_rect(px, Color(0.0, 0.0, 0.0, 0.12 * e))    # the threshold
	c.draw_rect(Rect2(leaf.position + Vector2(lerpf(3.0, 2.0, e), lerpf(5.0, 2.0, e)), leaf.size), Color(0, 0, 0, 0.3))
	c.draw_rect(leaf, Color(0.42, 0.3, 0.18).lerp(Color(0.45, 0.33, 0.2), e))
	if e < 0.85:
		var n := int(full / 8.0)
		for q in range(1, n):
			var o := float(q) * 8.0 * w / full
			if horiz:
				c.draw_line(Vector2(leaf.position.x + o, leaf.position.y + 2), Vector2(leaf.position.x + o, leaf.end.y - 2), Color(0.26, 0.18, 0.1), 2.0)
			else:
				c.draw_line(Vector2(leaf.position.x + 2, leaf.position.y + o), Vector2(leaf.end.x - 2, leaf.position.y + o), Color(0.26, 0.18, 0.1), 2.0)
	c.draw_rect(leaf, edge, false, lerpf(3.0, 2.0, e))
	if e < 0.5:
		c.draw_rect(Rect2(leaf.get_center() + (Vector2(-3, 6) if horiz else Vector2(6, -3)), Vector2(6, 6)), Color(0.8, 0.7, 0.3, 1.0 - 2.0 * e))    # the handle
	if e > 0.0:
		for p in [px.position, px.end]:
			c.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(edge, e))
