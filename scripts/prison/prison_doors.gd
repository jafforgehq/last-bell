## DOORS: a door in every doorway of the prison's buildings. In the clear phase they all start shut (solid for people and for the dead, so also for sight, shots and, through the wall count, for noise; the zone
## rule of the dormant dead already keeps a shut room's sleepers from hearing the next room) and E opens or shuts the one beside Ruth. The dead cannot open them. When the prison is secured the base is built
## again and every door is open for good (only drawn, no tile shut).
extends RefCounted

const Base := preload("res://scripts/prison/prison_base.gd")
const REACH := 1.7    # tiles from the doorway at which E answers

var game
var open: Array = []    # bool per Base.DOORS


func setup(g, clear: bool) -> void:
	game = g
	open.resize(Base.DOORS.size())
	open.fill(not clear)
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
	open[i] = not bool(open[i])
	_apply(i)
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


func paint(c: CanvasItem) -> void:
	var t: float = game.TILE
	var edge := Color(0.07, 0.06, 0.05)
	for i in open.size():
		var r := Rect2(Base.DOORS[i].rect)
		var px := Rect2(r.position * t, r.size * t)
		var horiz := r.size.x >= r.size.y
		if bool(open[i]):
			c.draw_rect(px, Color(0.0, 0.0, 0.0, 0.12))    # the threshold
			var leaf := Rect2(px.position + Vector2(0, -2), Vector2(5.0, t)) if horiz else Rect2(px.position + Vector2(-2, 0), Vector2(t, 5.0))    # swung back along the wall at the hinge end
			c.draw_rect(Rect2(leaf.position + Vector2(2, 2), leaf.size), Color(0, 0, 0, 0.3))
			c.draw_rect(leaf, Color(0.45, 0.33, 0.2))
			c.draw_rect(leaf, edge, false, 2.0)
			for p in [px.position, px.end]:
				c.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), edge)
		else:
			c.draw_rect(Rect2(px.position + Vector2(3, 5), px.size), Color(0, 0, 0, 0.3))
			c.draw_rect(px, Color(0.42, 0.3, 0.18))
			var n := int((px.size.x if horiz else px.size.y) / 8.0)
			for k in range(1, n):
				var o := float(k) * 8.0
				if horiz:
					c.draw_line(Vector2(px.position.x + o, px.position.y + 2), Vector2(px.position.x + o, px.end.y - 2), Color(0.26, 0.18, 0.1), 2.0)
				else:
					c.draw_line(Vector2(px.position.x + 2, px.position.y + o), Vector2(px.end.x - 2, px.position.y + o), Color(0.26, 0.18, 0.1), 2.0)
			c.draw_rect(px, edge, false, 3.0)
			c.draw_rect(Rect2(px.get_center() + (Vector2(-3, 6) if horiz else Vector2(6, -3)), Vector2(6, 6)), Color(0.8, 0.7, 0.3))    # the handle
