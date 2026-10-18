## DOORS: a door in every doorway of the prison's buildings. In the clear phase they all start shut (solid for people and for the dead, so also for sight, shots and, through the wall count, for noise; the zone
## rule of the dormant dead already keeps a shut room's sleepers from hearing the next room) and E opens or shuts the one beside Ruth. The dead cannot open them. When the prison is secured the base is built
## again and every door is open for good (only drawn, no tile shut).
extends RefCounted

const Base := preload("res://scripts/prison/prison_base.gd")
const REACH := 1.7    # tiles from the doorway at which E answers
const DUR := 0.3    # seconds every swing takes (open, shut, or turned back half way), eased out
const NEAR := 2.2    # managed base: tiles from a doorway at which Ruth or the crew make its leaves swing open (drawn only)
const FAR := 3.0    # managed base: a drawn door shuts only when nobody has been within this many tiles for LINGER seconds (no flapping at the NEAR edge)
const LINGER := 1.5
const KEEP := 1.0    # tiles: a door never shuts on a person (crew, ally) this near its doorway
const BODY := 0.4    # tiles: Ruth and the dead keep it open only from inside the doorway (so she can still shut it from the step, and shut it on the dead outside)
const AUTO := 1.4    # tiles from a shut doorway at which the crew, the allies and the bot open it
const LEAF := 11.0    # px thickness of a leaf (thick, so a shut door reads apart from the wall trim)
const STAGGER := 0.06    # seconds between the doors of the all-open event

var game
var open: Array = []    # bool per Base.doors(): the state asked for (E, the crew, the all-open event)
var solid: Array = []    # bool per door: the tiles are shut now. Opening makes them passable at once; shutting makes them solid only when the swing has ended and nobody stands in the way
var shown: Array = []    # bool per door: which way the drawn leaves are heading (same as `open`, but in the managed base they follow whoever walks by)
var clear := true
var node: CanvasItem    # the node that draws the leaves (redrawn every frame: a CanvasItem only repaints when asked)
var _from: Array = []    # float per door: how open it was drawn when it last started to move
var _t0: Array = []    # float per door: the time (`_now`) at which that move started
var _quiet: Array = []    # float per door: managed base, seconds nobody has been within FAR
var _log := false    # --doorlog: a DOOR line whenever someone waits at a door more than 2 s, a DOORLOG tally every 60 s
var _stall := {}    # --doorlog: person -> seconds waited at a door that is shut or still swinging
var _inside := {}    # --doorlog: person -> the door they are in (a pass is counted on the way in)
var _passes := 0
var _blocks := 0
var _next_tally := 60.0
var _now := 0.0    # seconds of door time, advanced by tick (so a paused or slowed game does not skip the swing)


func setup(g, clear_phase: bool) -> void:
	game = g
	clear = clear_phase
	var a = g.get("args")
	_log = a is Dictionary and a.has("doorlog")
	var n := Base.doors().size()
	open.resize(n)
	open.fill(not clear_phase)
	solid.resize(n)
	solid.fill(false)
	shown = open.duplicate()
	_from.resize(n)
	_from.fill(0.0 if clear_phase else 1.0)
	_t0.resize(n)
	_t0.fill(-100.0)
	_quiet.resize(n)
	_quiet.fill(0.0)
	if clear_phase:
		for i in n:
			_apply(i, true)


func _apply(i: int, shut_it: bool) -> void:
	solid[i] = shut_it
	var w = game.world
	var sim = game.run.sim
	var shut := 1 if shut_it else 0
	var r: Rect2i = Base.doors()[i].rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var k: int = y * w.W + x
			w.solid_p[k] = shut
			w.solid_z[k] = shut
			sim.path_p.set_solid(k, shut_it)
			sim.path_z.set_solid(k, shut_it)
	sim._regions_dirty = true


func _dist(i: int, p: Vector2) -> float:
	var r := Rect2(Base.doors()[i].rect)
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
	return {"kind": "door", "i": best, "label": "E: %s door (%s)" % ["close" if bool(open[best]) else "open", String(Base.doors()[best].name)]}


## Whoever is in the way keeps it from shutting: a crew member or an ally within KEEP of the doorway, Ruth or a dead one in it.
func _blocked(i: int) -> bool:
	if _dist(i, Vector2(game.run.avatar_p.x, game.run.avatar_p.y)) < BODY:
		return true
	for m in game.crew.members:
		if _dist(i, Vector2(m.p.x, m.p.y)) < KEEP:
			return true
	for z in game.run.sim.zombies:
		if z.state != "dead" and z.state != "dying" and _dist(i, Vector2(z.x, z.y)) < BODY:
			return true
	return false


## Opens or shuts door i; returns the line to say. Pressed again while it swings, it turns back from where it is.
func toggle(i: int) -> String:
	if bool(open[i]) and _blocked(i):
		return "Something is in the doorway."
	_turn(i, not bool(open[i]))
	return "Door open." if bool(open[i]) else "Door shut."


## Debug (--doortest): flips door i whatever stands in it (a shut still waits for the doorway to be empty).
func toggle_now(i: int) -> void:
	_turn(i, not bool(open[i]))


func _turn(i: int, want_open: bool, delay: float = 0.0) -> void:
	var cur := _k(i)
	open[i] = want_open
	if want_open and bool(solid[i]):
		_apply(i, false)    # passable from the first frame of the swing; shut only at its end (tick)
	_swing(i, cur, delay)


## The bot's way: a path as if every door were open (the walker then meets a door on it and opens it, `bot_open`).
func path(from: Vector2, to: Vector2) -> Array:
	var shut: Array = []
	for i in open.size():
		if bool(solid[i]):
			shut.append(i)
			_grid(i, false)
	var r: Array = game.run.sim.path_p.find(game.world.solid_p, from.x, from.y, to.x, to.y)
	for i in shut:
		_grid(i, true)
	return r


func _grid(i: int, s: bool) -> void:
	var r: Rect2i = Base.doors()[i].rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.run.sim.path_p.grid.set_point_solid(Vector2i(x, y), s)


## Opens every shut (or shutting) door within AUTO of `me`.
func bot_open(me: Vector2) -> void:
	for i in open.size():
		if not bool(open[i]) and _dist(i, me) < AUTO:
			_turn(i, true)


## How far a door is open, 0 (shut) to 1 (open): DUR seconds from where it was to where it is heading, eased out (fast start, soft stop), a stagger can delay the start.
func _k(i: int) -> float:
	var f := clampf((_now - float(_t0[i])) / DUR, 0.0, 1.0)
	return lerpf(float(_from[i]), 1.0 if bool(shown[i]) else 0.0, 1.0 - (1.0 - f) * (1.0 - f))


## Starts the swing of door i to its new state (from wherever it is now), `delay` seconds from now, with its sound.
func _swing(i: int, cur: float, delay: float = 0.0) -> void:
	shown[i] = open[i]
	_go(i, cur, delay)


func _go(i: int, cur: float, delay: float = 0.0) -> void:
	_from[i] = cur
	_t0[i] = _now + delay
	if not bool(shown[i]):
		delay += DUR * cur * 0.8    # FEEL: a shut is heard when the leaves meet (near the end of the swing), not as they start to move
	if delay <= 0.0:
		_sound(i)
	elif is_instance_valid(game) and game is Node and game.is_inside_tree():
		game.get_tree().create_timer(delay).timeout.connect(_sound.bind(i, float(_t0[i])))


## Every frame. Clear phase: a crew member or an ally who comes to a shut door opens it, and a door that has swung shut turns solid (or, when someone stepped into it meanwhile, swings open again).
## Managed base (doors open for good, only drawn): a door swings open when Ruth or one of the crew comes within NEAR and shuts when nobody has been within FAR for LINGER seconds. Then repaints the leaves.
func tick(dt: float) -> void:
	_now += dt
	if not is_instance_valid(game):
		return
	if clear:
		if game.crew != null:
			for m in game.crew.members:
				if bool(m.p.moving):    # (one who stands by does not undo the door Ruth just shut)
					bot_open(Vector2(m.p.x, m.p.y))
		for i in open.size():
			if not bool(open[i]) and not bool(solid[i]) and _k(i) <= 0.0:
				if _blocked(i):
					_turn(i, true)
				else:
					_apply(i, true)
	else:
		var who: Array = [Vector2(game.run.avatar_p.x, game.run.avatar_p.y)]
		if game.crew != null:
			for m in game.crew.members:
				who.append(Vector2(m.p.x, m.p.y))
		for i in open.size():
			var d := INF
			for p in who:
				d = minf(d, _dist(i, p))
			_quiet[i] = 0.0 if d < FAR else float(_quiet[i]) + dt
			var want: bool = d < NEAR or (bool(shown[i]) and float(_quiet[i]) < LINGER)
			if want != bool(shown[i]):
				var cur := _k(i)
				shown[i] = want
				_go(i, cur)
	if _log:
		_watch(dt)
	if node != null:
		node.queue_redraw()


## --doorlog: counts each pass through a doorway and prints a DOOR line when a person walking has been at a door for more than 2 s while it was shut or not yet open enough to walk through.
func _watch(dt: float) -> void:
	var who := {"Ruth": game.run.avatar_p}
	if game.crew != null:
		for m in game.crew.members:
			who[String(m.def.get("name", "?"))] = m.p
	for nm in who:
		var p := Vector2(who[nm].x, who[nm].y)
		var at := -1
		for i in open.size():
			if _dist(i, p) < 0.9:
				at = i
		var inside := at >= 0 and _dist(at, p) == 0.0
		if inside and int(_inside.get(nm, -1)) != at:
			_passes += 1
		_inside[nm] = at if inside else -1
		if at >= 0 and bool(who[nm].moving) and (bool(solid[at]) or _k(at) < 0.8):    # (one who stands working beside a shut door is not held up by it)
			_stall[nm] = float(_stall.get(nm, 0.0)) + dt
			if float(_stall[nm]) - dt <= 2.0 and float(_stall[nm]) > 2.0:
				_blocks += 1
				print("DOOR blocked ", nm, " at ", Base.doors()[at].name, " ", Base.doors()[at].rect, " t=", snappedf(_now, 0.1), " solid ", solid[at], " k ", snappedf(_k(at), 0.01))
		else:
			_stall[nm] = 0.0
	if _now >= _next_tally:
		_next_tally += 60.0
		print("DOORLOG t=", int(_now), " people ", who.size(), " passes ", _passes, " blocked ", _blocks)


## A short sound at the door, wood for a plain door and steel for a cell block's.
func _sound(i: int, t0 := INF) -> void:
	if not is_instance_valid(game) or game.audio == null or (t0 != INF and t0 != float(_t0[i])):    # (a late sound of a swing that was turned back meanwhile is dropped)
		return
	var at := Rect2(Base.doors()[i].rect).get_center()
	var o := bool(shown[i])
	var cell := String(Base.doors()[i].name) == "Cell block"
	var rng := randf_range(0.95, 1.05)
	if cell:
		game.audio.sfx("pd_cell_open_0" if o else "pd_cell_slam_%d" % randi_range(0, 1), -5.0, rng, "SFX", 0.05, at, 26.0)    # (the slam: a recording that was imported and never played)
	else:
		game.audio.sfx("pd_wood_open_0" if o else "pd_wood_close_0", -1.0, rng, "SFX", 0.05, at, 24.0)


## The all-open event after the last zone: every shut door swings open one after the other (about 0.06 s apart). Returns how long the whole thing takes, in seconds.
func open_all() -> float:
	var n := 0
	for i in open.size():
		if not bool(open[i]):
			_turn(i, true, float(n) * STAGGER)
			n += 1
	return DUR + float(maxi(n - 1, 0)) * STAGGER if n > 0 else 0.0


func paint(c: CanvasItem) -> void:
	for i in open.size():
		_paint_door(c, i, _k(i))


## Which way door i swings: always into the building it belongs to (the side of the doorway inside one of the building rects), else the north or west side. Returns the unit normal.
static func side(r: Rect2) -> Vector2:
	var horiz := r.size.x >= r.size.y
	var n := Vector2(0, -1) if horiz else Vector2(-1, 0)
	var b := r.get_center() - n * ((r.size.y if horiz else r.size.x) * 0.5 + 0.5)
	for rb in [Base.CELLS, Base.CANTEEN, Base.INFIRMARY, Base.WORKSHOP, Base.STORES, Base.GARDEN]:
		if Rect2(rb).grow(-0.5).has_point(b):
			return -n
	return n


## The two leaves of a doorway at progress k (0 shut, 1 open), in tiles: quads of `thick` tiles. Each is hinged at an end of the doorway, set in by half its thickness so that, open, it lies along the
## jamb inside the doorway's own span and never over the wall beside it; shut they meet in the middle. Opening turns each about its hinge through 90 degrees toward `norm` (into the room).
static func leaves(r: Rect2, norm: Vector2, k: float, thick: float) -> Array:
	var horiz := r.size.x >= r.size.y
	var along := Vector2(1, 0) if horiz else Vector2(0, 1)
	var full: float = r.size.x if horiz else r.size.y
	var centre := r.get_center()
	var hw := thick * 0.5
	var ll := full * 0.5 - hw
	var ang := k * (PI * 0.5)
	var out: Array = []
	for h in 2:
		var dir := along if h == 0 else -along    # the way the leaf points when shut
		var hinge := centre - dir * (full * 0.5 - hw)
		var d := dir * cos(ang) + norm * sin(ang)
		var nrm := Vector2(-d.y, d.x)
		out.append(PackedVector2Array([hinge + nrm * hw, hinge + d * ll + nrm * hw, hinge + d * ll - nrm * hw, hinge - nrm * hw]))
	return out


## One door at progress k: two leaves (a thick plank slab with a dark outline) with a hinge plate and pin each, the handles while shut.
func _paint_door(c: CanvasItem, i: int, k: float) -> void:
	var t: float = game.TILE
	var edge := Color(0.07, 0.06, 0.05)
	var r := Rect2(Base.doors()[i].rect)
	var steel := String(Base.doors()[i].name) == "Cell block"
	var px := Rect2(r.position * t, r.size * t)
	if k > 0.0:
		c.draw_rect(px, Color(0.0, 0.0, 0.0, 0.18 * k))    # the dark threshold the open doorway shows
	var fill := Color(0.6, 0.42, 0.22) if not steel else Color(0.52, 0.55, 0.6)
	var grain := Color(0.26, 0.18, 0.1) if not steel else Color(0.25, 0.27, 0.3)
	var hw := LEAF * 0.5
	for lq in leaves(r, side(r), k, LEAF / t):
		var q := PackedVector2Array()
		for v in lq:
			q.append(v * t)
		var hinge := (q[0] + q[3]) * 0.5
		var tip := (q[1] + q[2]) * 0.5
		var ll := hinge.distance_to(tip)
		var d := (tip - hinge) / ll
		var nrm := Vector2(-d.y, d.x)
		var sh := PackedVector2Array()
		for v in q:
			sh.append(v + Vector2(2, 3))
		c.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
		c.draw_colored_polygon(q, fill)
		for s in range(1, int(ll / 8.0)):
			var m := hinge + d * (float(s) * 8.0)
			c.draw_line(m + nrm * (hw - 1.0), m - nrm * (hw - 1.0), grain, 1.5)
		q.append(q[0])
		c.draw_polyline(q, edge, 3.0)
		c.draw_rect(Rect2(hinge - Vector2(hw + 1.0, hw + 1.0), Vector2(hw + 1.0, hw + 1.0) * 2.0), edge)    # the hinge: a dark plate with a brass pin
		c.draw_circle(hinge, 2.5, Color(0.85, 0.7, 0.35))
	if k < 0.5:
		var horiz := r.size.x >= r.size.y
		var along := Vector2(1, 0) if horiz else Vector2(0, 1)
		for sgn in [-1.0, 1.0]:
			c.draw_circle(px.get_center() + along * 6.0 * sgn, 2.5, Color(0.8, 0.7, 0.3, 1.0 - 2.0 * k))    # the handles
