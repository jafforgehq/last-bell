## One doorway of a house on the screen (One House, WP2). A door NEVER blocks (the rules treat a doorway as an opening: scripts/town/town_gen.gd); this is only its
## picture: it swings open (SWING_S) while somebody is near it and shuts SHUT_AFTER seconds after the last one has gone, unless it is WEDGED open (a look-in through
## it, `wedged = true`, which the house view sets and releases). The art kit's door pictures are used when the manifest has them (TownArt.door: closed and open
## states, cross-faded over the swing; a two tile doorway is two doors, the kit's two variants hinged on opposite sides), else a flat leaf that swings on its hinge.
##
## `setup(door, passage_ns, inward, variant)`: `door` is a town door ({"tiles": [Vector2i], "exterior": bool, "side": ...}), `passage_ns` true when people walk through
## it north to south (the wall runs along x), `inward` the direction the leaf swings to (into the house, or to the side of an inner door). `tick(dt, near)` is called
## every frame by the house view with whether a pawn is within its reach.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TownArt := preload("res://scripts/town/town_art.gd")

const TILE := GD.TILE
const SWING_S := 0.18
const SHUT_AFTER := 0.5
const LEAF := 0.26
const POST := 0.2

## The doorway in tiles: its top left tile and its size, and its middle (where "near" is measured from).
var rect_t := Rect2()
var center := Vector2.ZERO
var exterior := false
## The house it belongs to and the rooms on its two sides (-1: none), set by the house view.
var house := -1
var room_a := -1
var room_b := -1
## Whether a pawn is within reach (the house view measures it a few times a second) and whether a look-in holds the door open.
var near_now := false
var wedged := false
## 0 shut .. 1 open (the swing), and whether the door is asked to be open now (somebody near, wedged, or not yet 0.5 s since the last one left).
var open_t := 0.0
var open_target := false
var _idle := 99.0
var _ns := true
var _inward := Vector2.DOWN
var _facing := "s"
var _variant := 0
var _tiles: Array = []
var _art_closed: Array = []
var _art_open: Array = []


func setup(door: Dictionary, passage_ns: bool, inward: Vector2, variant: int = 0) -> void:
	exterior = bool(door.exterior)
	_ns = passage_ns
	_inward = inward
	_variant = variant
	_tiles = door.tiles
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for t in _tiles:
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	rect_t = Rect2(Vector2(lo), Vector2(hi - lo + Vector2i.ONE))
	center = rect_t.get_center()
	position = rect_t.position * TILE
	if exterior:
		_facing = String(door.side).to_lower()
	else:
		_facing = "s" if _ns else "e"
	var kind := "front" if exterior else "interior"
	_art_closed.clear()
	_art_open.clear()
	for i in _tiles.size():
		_art_closed.append(TownArt.door(kind, _facing, "closed", _variant + i))
		_art_open.append(TownArt.door(kind, _facing, "open", _variant + i))
	queue_redraw()


## One frame: `near` is whether a pawn is within the door's reach.
func tick(dt: float, near: bool) -> void:
	if near:
		_idle = 0.0
	else:
		_idle += dt
	open_target = near or wedged or _idle < SHUT_AFTER
	var want := 1.0 if open_target else 0.0
	if open_t != want:
		open_t = move_toward(open_t, want, dt / SWING_S)
		queue_redraw()


func _draw() -> void:
	var size_px := rect_t.size * TILE
	if not _art_closed.is_empty() and not _art_closed[0].placeholder:
		_draw_art()
		return
	var along_x := _ns
	var a := Vector2.RIGHT if along_x else Vector2.DOWN
	var length := size_px.x if along_x else size_px.y
	var start := Vector2(0.0, size_px.y * 0.5) if along_x else Vector2(size_px.x * 0.5, 0.0)
	var col: Color = _art_closed[0].color if not _art_closed.is_empty() else Color("85633f")
	# a doorway of two tiles is a pair of leaves hinged at its two posts, one tile long each; a doorway of one tile has one leaf
	var leaves := 2 if _tiles.size() >= 2 else 1
	var each := length / float(leaves)
	for i in leaves:
		var hinge := start if i == 0 else start + a * length
		var dir := a if i == 0 else -a
		var rot := dir.angle() + open_t * dir.angle_to(_inward) * 0.96
		_leaf(hinge, rot, each, col)
	# the frame posts at both ends of the doorway
	var pw := POST * TILE
	var post_col := Color(0.2, 0.15, 0.1)
	draw_rect(Rect2(start - Vector2(pw, pw) * 0.5, Vector2(pw, pw)), post_col)
	draw_rect(Rect2(start + a * length - Vector2(pw, pw) * 0.5, Vector2(pw, pw)), post_col)


## One leaf of the door: a plank slab on its hinge, shut it lies in the doorway, open it has swung to the way people come through.
func _leaf(hinge: Vector2, rot: float, length: float, col: Color) -> void:
	var th := LEAF * TILE
	draw_set_transform(hinge, rot, Vector2.ONE)
	var leaf := Rect2(0.0, -th * 0.5, length, th)
	draw_rect(Rect2(leaf.position + Vector2(1, 3), leaf.size), Color(0, 0, 0, 0.3))
	draw_rect(leaf, col)
	draw_rect(Rect2(leaf.position + Vector2(2, 2), leaf.size - Vector2(4, 4)), col.lightened(0.16))
	draw_rect(leaf, col.darkened(0.55), false, 2.0)
	draw_circle(Vector2(length - 0.14 * TILE, 0.0), 0.05 * TILE, Color(0.9, 0.8, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_art() -> void:
	for i in _tiles.size():
		var origin := (Vector2(_tiles[i]) - rect_t.position) * TILE
		var rect := Rect2(origin, Vector2(TILE, TILE))
		# the kit's pictures are whole cells (floor and frame included): the open one fades in over the shut one
		if open_t < 1.0:
			TownArt.draw(self, _art_closed[i], rect)
		if open_t > 0.0:
			TownArt.draw(self, _art_open[i], rect, Color(1, 1, 1, open_t))
