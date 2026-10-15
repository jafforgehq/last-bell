## DOORS: a door in every doorway of the prison's buildings. In the clear phase they all start shut (solid for people and for the dead, so also for sight, shots and, through the wall count, for noise; the zone
## rule of the dormant dead already keeps a shut room's sleepers from hearing the next room) and E opens or shuts the one beside Ruth. The dead cannot open them. When the prison is secured the base is built
## again and every door is open for good (only drawn, no tile shut).
extends RefCounted

const Base := preload("res://scripts/prison/prison_base.gd")
const REACH := 1.7    # tiles from the doorway at which E answers
const DUR := 0.3    # seconds a door takes to swing open or shut
const NEAR := 2.2    # managed base: tiles from a doorway at which Ruth or the crew make its leaves swing open (drawn only)
const LEAF := 7.0    # px thickness of a leaf
const STAGGER := 0.06    # seconds between the doors of the all-open event

var game
var open: Array = []    # bool per Base.DOORS (the real state: the tiles are shut or not)
var shown: Array = []    # bool per door: which way the drawn leaves are heading (same as `open`, but in the managed base they follow whoever walks by)
var clear := true
var node: CanvasItem    # the node that draws the leaves (redrawn every frame: a CanvasItem only repaints when asked)
var _from: Array = []    # float per door: how open it was drawn when it last started to move
var _t0: Array = []    # float per door: the time (`_now`) at which that move started
var _now := 0.0    # seconds of door time, advanced by tick (so a paused or slowed game does not skip the swing)


func setup(g, clear_phase: bool) -> void:
	game = g
	clear = clear_phase
	open.resize(Base.DOORS.size())
	open.fill(not clear_phase)
	shown = open.duplicate()
	_from.resize(open.size())
	_from.fill(0.0 if clear_phase else 1.0)
	_t0.resize(open.size())
	_t0.fill(-100.0)
	if clear_phase:
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


## Debug (--doortest): flips door i whatever stands in it.
func toggle_now(i: int) -> void:
	var cur := _k(i)
	open[i] = not bool(open[i])
	_apply(i)
	_swing(i, cur)


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


## How far a door is open, 0 (shut) to 1 (open), eased: it moves for DUR seconds after `_go` (a stagger can delay the start).
func _k(i: int) -> float:
	var f := clampf((_now - float(_t0[i])) / DUR, 0.0, 1.0)
	return lerpf(float(_from[i]), 1.0 if bool(shown[i]) else 0.0, f)


## Starts the swing of door i to its new state (from wherever it is now), `delay` seconds from now, with its sound.
func _swing(i: int, cur: float, delay: float = 0.0) -> void:
	shown[i] = open[i]
	_go(i, cur, delay)


func _go(i: int, cur: float, delay: float = 0.0) -> void:
	_from[i] = cur
	_t0[i] = _now + delay
	if delay <= 0.0:
		_sound(i)
	elif is_instance_valid(game) and game.is_inside_tree():
		game.get_tree().create_timer(delay).timeout.connect(_sound.bind(i))


## Every frame: repaints the leaves (a CanvasItem only repaints when asked, which is why the swing was never seen), and in the managed base (doors open for good, only drawn) swings a door open while
## Ruth or one of the crew is near it and shut again when they have gone.
func tick(dt: float) -> void:
	_now += dt
	if clear and is_instance_valid(game) and game.crew != null:
		for m in game.crew.members:    # a crew member or ally who comes to a shut door opens it
			for i in open.size():
				if not bool(open[i]) and _dist(i, Vector2(m.p.x, m.p.y)) < 1.0:
					toggle_now(i)
	if not clear and is_instance_valid(game):
		var who: Array = [Vector2(game.run.avatar_p.x, game.run.avatar_p.y)]
		for m in game.crew.members:
			who.append(Vector2(m.p.x, m.p.y))
		for i in open.size():
			var want := false
			for p in who:
				if _dist(i, p) < NEAR:
					want = true
					break
			if want != bool(shown[i]):
				var cur := _k(i)
				shown[i] = want
				_go(i, cur)
	if node != null:
		node.queue_redraw()


## A short sound at the door, wood for a plain door and steel for a cell block's.
func _sound(i: int) -> void:
	if not is_instance_valid(game) or game.audio == null:
		return
	var at := Rect2(Base.DOORS[i].rect).get_center()
	var o := bool(shown[i])
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


## Which way door i swings: to the side of the doorway that lies inside a zone (the room), else the north or west side. Returns the unit normal.
func _side(i: int) -> Vector2:
	var r := Rect2(Base.DOORS[i].rect)
	var horiz := r.size.x >= r.size.y
	var n := Vector2(0, -1) if horiz else Vector2(-1, 0)
	var mid := r.get_center()
	var off: float = (r.size.y if horiz else r.size.x) + 0.5
	var a := mid + n * off
	var b := mid - n * off
	return -n if (Base.zone_at(b.x, b.y) >= 0 and Base.zone_at(a.x, a.y) < 0) else n


## One door at progress k: two leaves (a thick plank slab with a dark outline) hinged at the two ends of the doorway, each half its length. Shut they meet in the middle; opening turns each about its
## hinge through 90 degrees into the room, so the doorway is clear and the leaves stand across the wall line.
func _paint_door(c: CanvasItem, i: int, k: float) -> void:
	var t: float = game.TILE
	var edge := Color(0.07, 0.06, 0.05)
	var e := k * k * (3.0 - 2.0 * k)
	var r := Rect2(Base.DOORS[i].rect)
	var horiz := r.size.x >= r.size.y
	var steel := String(Base.DOORS[i].name) == "Cell block"
	var px := Rect2(r.position * t, r.size * t)
	var along := Vector2(1, 0) if horiz else Vector2(0, 1)
	var norm := _side(i)
	var full: float = px.size.x if horiz else px.size.y
	var centre := px.get_center()
	if e > 0.0:
		c.draw_rect(px, Color(0.0, 0.0, 0.0, 0.18 * e))    # the dark threshold the open doorway shows
	var fill := Color(0.42, 0.3, 0.18) if not steel else Color(0.38, 0.4, 0.43)
	var grain := Color(0.26, 0.18, 0.1) if not steel else Color(0.25, 0.27, 0.3)
	var ang := e * (PI * 0.5)
	var hw := LEAF * 0.5
	var ll := full * 0.5
	for h in 2:
		var hinge := centre - along * full * 0.5 if h == 0 else centre + along * full * 0.5
		var dir := along if h == 0 else -along    # the way the leaf points when shut
		var d := dir * cos(ang) + norm * sin(ang)    # turned toward `norm`: 90 degrees ends up along it
		var nrm := Vector2(-d.y, d.x)
		var q := PackedVector2Array([hinge + nrm * hw, hinge + d * ll + nrm * hw, hinge + d * ll - nrm * hw, hinge - nrm * hw])
		var sh := PackedVector2Array()
		for v in q:
			sh.append(v + Vector2(2, 3))
		c.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
		c.draw_colored_polygon(q, fill)
		for s in range(1, int(ll / 8.0)):
			var m := hinge + d * (float(s) * 8.0)
			c.draw_line(m + nrm * (hw - 1.0), m - nrm * (hw - 1.0), grain, 1.5)
		q.append(q[0])
		c.draw_polyline(q, edge, 2.0)
		c.draw_circle(hinge, 3.0, edge)    # the hinge
	if e < 0.5:
		for sgn in [-1.0, 1.0]:
			c.draw_circle(centre + along * 6.0 * sgn, 2.5, Color(0.8, 0.7, 0.3, 1.0 - 2.0 * e))    # the handles
