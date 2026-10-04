## The things inside the houses that change in play (One House, WP2), a view part of the town facade: the claimed base's props (bed, stash, radio, bench: `sim.base.props()`,
## the layout's interior list {id, kind, pos (the middle, tiles), room, face "N|E|S|W"}) and the open look of the containers that have been searched
## (`sim.search.is_looted(container id)`, drawn over the furniture's own picture at the container's `at`). Both are one painter node under the people and over the floor
## and the furniture of the world; it redraws only when what it shows changes (checked twice a second for the houses near the view, or when an event says so).
## Pictures come from TownArt (the kit's when it has them, else flat shapes). Every source is soft: no `base`, no `search` is nothing to draw.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TownArt := preload("res://scripts/town/town_art.gd")

const TILE := GD.TILE
const EVERY := 0.5
const NEAR := 10.0

var sim
var houses
var search
var base

var _view := Rect2()
var _t := 0.0
var _sig := 0
var _items: Array = []
var _list: Array = []
var _painter: Painter


func _init() -> void:
	z_index = 4
	_painter = Painter.new()
	_painter.name = "Painter"
	add_child(_painter)


func on_ready(main) -> void:
	var world = main.get("world")
	if world != null and get_parent() == null:
		world.add_child(self)
	var s = main.get("sim")
	bind(s, s.get("houses"), s.get("search"), s.get("base"))


func bind(the_sim, the_houses, the_search = null, the_base = null) -> void:
	sim = the_sim
	houses = the_houses
	search = the_search
	base = the_base
	_list = []
	_sig = 0
	_items = []
	if houses == null:
		return
	var t = houses.get("town")
	if t is Dictionary and not t.is_empty():
		_list = t.houses


func on_sync_views(view: Rect2) -> void:
	_view = view


func on_event(e: Dictionary) -> void:
	var kind := String(e.get("type", ""))
	if kind == "searched" or kind == "claimed":
		_t = 0.0


func on_frame(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = EVERY
	refresh()


## Looks at the base's props and the looted containers near the view and redraws if they are not what was drawn. Returns the number of things shown.
func refresh() -> int:
	var items: Array = []
	if base != null:
		for p in base.props():
			var kind := String(p.get("kind", p.get("id", "")))
			items.append({"kind": kind, "at": Vector2(p.pos), "face": String(p.get("face", "S")), "state": "", "open": false})
	if search != null and houses != null:
		var region := _region()
		for hd in _list:
			if not region.intersects(Rect2(hd.rect)):
				continue
			for c in houses.containers_of(int(hd.id)):
				if search.is_looted(String(c.id)):
					items.append({"kind": String(c.kind), "at": Vector2(c.at), "face": "S", "state": "open", "open": true})
	var sig := hash(items)
	if sig != _sig or items.size() != _items.size():
		_sig = sig
		_items = items
		_painter.items = items
		_painter.queue_redraw()
	return _items.size()


func _region() -> Rect2:
	if _view.has_area():
		return _view.grow(NEAR)
	var av = sim.avatar.player() if sim != null and sim.get("avatar") != null else null
	if av != null:
		return Rect2(Vector2(av.x, av.y) - Vector2(30, 30), Vector2(60, 60))
	return Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)


## What is shown now: a list of {kind, at, face, state, open} (a test reads it).
func shown() -> Array:
	return _items


## Draws the items. Not one allocation a frame: it is drawn only when the list changes.
class Painter extends Node2D:
	const TILE_PX := 64.0
	const LINE := Color("221a13")
	var items: Array = []

	func _draw() -> void:
		for it in items:
			var d: Dictionary = TownArt.prop(String(it.kind), String(it.state), String(it.face).to_lower())
			var size: Vector2 = d.size
			if String(it.face) == "E" or String(it.face) == "W":
				size = Vector2(size.y, size.x)
			var rect := Rect2((Vector2(it.at) - size * 0.5) * TILE_PX, size * TILE_PX)
			if not bool(d.placeholder) and TownArt.texture(d) != null:
				TownArt.draw(self, d, rect)
			elif bool(it.open):
				_open(Vector2(it.at) * TILE_PX)
			else:
				_flat(String(it.kind), String(it.face), rect, d.color)

	## A searched container: a dark opening with a pale rim over the furniture.
	func _open(c: Vector2) -> void:
		var r := Rect2(c - Vector2(0.28, 0.18) * TILE_PX, Vector2(0.56, 0.36) * TILE_PX)
		draw_rect(r, Color(0.1, 0.08, 0.06, 0.92))
		draw_rect(r, Color(0.8, 0.75, 0.62, 0.8), false, 2.0)
		draw_line(r.position + Vector2(3, 0), r.position + Vector2(r.size.x - 3, 0), Color(0.9, 0.85, 0.7, 0.9), 3.0)

	func _flat(kind: String, face: String, r: Rect2, col: Color) -> void:
		var pad := 0.06 * TILE_PX
		var body := r.grow(-pad)
		draw_rect(Rect2(body.position + Vector2(3, 4), body.size), Color(0, 0, 0, 0.25))
		draw_rect(body, col)
		match kind:
			"bed":
				# the head (a pillow) is at the end away from the way the bed faces
				var tall := r.size.y >= r.size.x
				var pil := Vector2(body.size.x * 0.8, 0.28 * TILE_PX) if tall else Vector2(0.28 * TILE_PX, body.size.y * 0.8)
				var at_start := face == "S" or face == "E"
				var pos := body.position + (body.size - pil) * 0.5
				if tall:
					pos.y = body.position.y + 4.0 if at_start else body.end.y - pil.y - 4.0
				else:
					pos.x = body.position.x + 4.0 if at_start else body.end.x - pil.x - 4.0
				draw_rect(body.grow(-1), col.lightened(0.12), false, 2.0)
				draw_rect(Rect2(pos, pil), Color(0.92, 0.9, 0.84))
			"stash":
				draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.4), Vector2(body.size.x, body.size.y * 0.2)), col.darkened(0.3))
				draw_rect(body.grow(-3), col.lightened(0.15), false, 2.0)
			"radio":
				draw_rect(Rect2(body.position + body.size * Vector2(0.15, 0.2), body.size * Vector2(0.45, 0.45)), Color(0.75, 0.82, 0.6))
				draw_circle(body.position + body.size * Vector2(0.75, 0.6), body.size.x * 0.1, Color(0.85, 0.8, 0.6))
				draw_line(body.position + body.size * Vector2(0.85, 0.1), body.position + body.size * Vector2(0.95, -0.25), Color(0.7, 0.7, 0.7), 2.0)
			"bench":
				draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.15), Vector2(body.size.x, body.size.y * 0.7)), col.lightened(0.1))
				draw_rect(Rect2(body.position + body.size * Vector2(0.1, 0.25), body.size * Vector2(0.14, 0.5)), Color(0.35, 0.35, 0.38))
		draw_rect(body, LINE, false, 2.0)
