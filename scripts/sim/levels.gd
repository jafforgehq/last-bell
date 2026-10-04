## The two levels of the yard: the GROUND and the DECKS (round 24, "levels"). A deck is the north wall's catwalk, the side walkways and the two corner
## towers: raised, reached ONLY by a ladder (the ladder tiles, scripts/world.gd `_apply_deck_barriers`). In the grids a deck tile and a ground tile are
## neighbours, so the world keeps them apart with solid tiles: the face under the catwalk and the inner edge of the side walkways. Three places did not:
##   - the corner towers: their outer sides (the street north of them, the ground west or east of them) were open, so anyone could step off a tower or
##     onto it from the street. `_hold` makes that ring of ground solid (both walking grids and both path grids) for the avatar's game;
##   - the gate's mouth: the catwalk crosses the gateway on the bridge (the mouth's row 18, columns 37 to 40), so that one tile is the bridge deck AND the
##     passage under it. With the gate open a person in the passage could step sideways onto the catwalk, and one on the bridge could step down into the
##     passage, without a ladder, and a person in the passage counted as on the deck. Here a person in those four tiles has a LEVEL, the one they came in
##     with (from the catwalk's tiles beside the mouth: the deck; from the passage above or below it: the ground): the ground may not step onto the
##     catwalk's tiles beside the mouth and the deck may not step down into the passage (`blocks`, which the avatar's walking asks; `find_path`, which the
##     crew's walking asks; the dead are kept off the catwalk by `_hold`);
##   - what is done from a level: a post on a deck (a spot the avatar's feet are put on) is taken only from that deck, the gate's lever (on the ground)
##     only from the ground, a wall is mended from the level its mending place is on (scripts/sim/interact.gd, nights.gd).
## Everything is behind avatar mode (`sim.player_id != ""`): with no avatar nothing here changes a grid, a path or an answer, and `on_deck` is the world's.
## Nothing is saved: the levels of the people on the bridge are worked out again from where they are (a person met there with no past is on the deck).
extends RefCounted

const Gate := preload("res://scripts/sim/gate.gd")

## The catwalk's row, the columns of the gateway's mouth and the catwalk's tiles on each side of it, the rows of the passage above and below it.
const WALK_ROW := 18
const ABUTMENTS := [36, 41]
const PASSAGE_ROWS := [17, 19]
## Where a person on the ground is under the bridge's planks (tiles): the views draw them below it.
const UNDER := Rect2(36.9, 17.9, 4.2, 3.1)

var sim
## Whether the levels are kept at all in an avatar game (a test that plays the game as it was before them switches it off).
var enabled := true
## The ground made solid round the towers, and the catwalk's tiles beside the mouth made solid for the dead (`solid_z`), while the avatar's game runs.
var _ring: Array = []
var _cut: Array = []
var _held := false
## Who is on the bridge deck while in a tile of the mouth's catwalk row (id -> bool: true on the deck, false in the passage), and the tile each person was
## in at the last step.
var _deck := {}
var _tile := {}


func setup(s) -> void:
	sim = s


## A new run: nothing remembered (the grids are made again with the world).
func start() -> void:
	_deck.clear()
	_tile.clear()
	if _held:
		_release()


## Whether the levels are kept: avatar mode.
func active() -> bool:
	# (not in a place: a trip's map has its own size and no compound, decks or gate: `nights_on` is false in a RaidSim, as for the gate and the nights)
	return enabled and sim != null and bool(sim.nights_on) and String(sim.player_id) != ""


# ---------------------------------------------------------------------------------------------------- the world --

## The ground tiles that touch a tower's deck from outside (walkable, not deck): the street and the ground beside the corner.
func _tower_ring() -> Array:
	var out: Array = []
	var seen := {}
	var w = sim.world
	for o in w.d.objects:
		if String(o.kind) != "tower":
			continue
		var c0 := floori(float(o.cx) - float(o.w) / 2.0)
		var c1 := floori(float(o.cx) + float(o.w) / 2.0 - 0.001)
		var r0 := floori(float(o.cy) - float(o.h) / 2.0)
		var r1 := floori(float(o.cy) + float(o.h) / 2.0 - 0.001)
		for r in range(r0 - 1, r1 + 2):
			for c in range(c0 - 1, c1 + 2):
				var inside_c := c >= c0 and c <= c1
				var inside_r := r >= r0 and r <= r1
				if inside_c == inside_r:
					continue    # (the tower itself, and the corners that only touch it)
				if c < 0 or r < 0 or c >= w.W or r >= w.H:
					continue
				var i: int = r * w.W + c
				if seen.has(i) or w.solid_p[i] != 0 or w.deck_tiles.has(i):
					continue
				seen[i] = true
				out.append(i)
	return out


## Puts the levels' solid tiles in (the first step of an avatar's game).
func _hold() -> void:
	_held = true
	_ring = _tower_ring()
	if not _ring.is_empty():
		sim.block_tiles(_ring, true)
	# (the dead stay on the ground: with the gate open they may walk the passage, not step from it onto the catwalk beside it)
	_cut = []
	for c in ABUTMENTS:
		var i: int = WALK_ROW * int(sim.W) + int(c)
		if int(sim.world.solid_z[i]) == 0:
			sim.world.solid_z[i] = 1
			sim.path_z.set_solid(i, true)
			_cut.append(i)


## Takes them out again (the avatar's game is over: a test that goes back to the old yard).
func _release() -> void:
	_held = false
	if not _ring.is_empty():
		sim.block_tiles(_ring, false)
	_ring = []
	for i in _cut:
		sim.world.solid_z[int(i)] = 0
		sim.path_z.set_solid(int(i), false)
	_cut = []


# ----------------------------------------------------------------------------------------------------- the people --

func _index(x: float, y: float) -> int:
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= int(sim.W) or ty >= int(sim.H):
		return -1
	return ty * int(sim.W) + tx


## Whether the tile is one of the mouth's catwalk row (the bridge over the passage).
func _in_bridge(i: int) -> bool:
	if i < 0:
		return false
	@warning_ignore("integer_division")
	return Gate.MOUTH_COLS.has(i % int(sim.W)) and i / int(sim.W) == WALK_ROW


## Whether a point is in the mouth's catwalk row (the bridge tile that is also the passage).
func in_bridge_tile(x: float, y: float) -> bool:
	return _in_bridge(_index(x, y))


## What a person who steps into the bridge's tile from tile `was` is: on the deck if they came from the catwalk beside it (or from nowhere: a person
## put there is on the catwalk), in the passage if they came from the rows above or below.
func _came_from_deck(was: int) -> bool:
	if was < 0:
		return true
	@warning_ignore("integer_division")
	var col: int = was % int(sim.W)
	@warning_ignore("integer_division")
	var row: int = was / int(sim.W)
	if row == WALK_ROW and ABUTMENTS.has(col):
		return true
	if PASSAGE_ROWS.has(row) and Gate.MOUTH_COLS.has(col):
		return false
	return true


## Each step (after the gate's): who is in the bridge's tiles, and on which level.
func update(_dt: float) -> void:
	if not active():
		if _held:
			_release()
		_deck.clear()
		_tile.clear()
		return
	if not _held:
		_hold()
	var seen := {}
	for p in sim.people:
		if p.dead or p.turned or p.away != null:
			continue
		var id := String(p.id)
		seen[id] = true
		var i := _index(p.x, p.y)
		var was: int = int(_tile.get(id, -1))
		_tile[id] = i
		if _in_bridge(i):
			if not _in_bridge(was):
				_deck[id] = _came_from_deck(was)
		else:
			_deck.erase(id)
	for id in _tile.keys():
		if not seen.has(id):
			_tile.erase(id)
			_deck.erase(id)


## Whether a person is on a raised deck: the world's answer, except in the bridge's tiles, where it is the level they came in with (the tile they were in
## at the last step says where they came from, if this step is the one that brought them in).
func on_deck(p) -> bool:
	if not active() or not _in_bridge(_index(p.x, p.y)):
		return sim.world.on_deck(p.x, p.y)
	var id := String(p.id)
	var was: int = int(_tile.get(id, -1))
	if _in_bridge(was):
		return bool(_deck.get(id, true))
	return _came_from_deck(was)


## Whether a person is in the passage under the bridge, below its planks (a view draws them under the bridge): on the ground and in its footprint.
func under_bridge(p) -> bool:
	return active() and UNDER.has_point(Vector2(p.x, p.y)) and not on_deck(p)


## The same for one of the dead (always on the ground).
func under_bridge_dead(z) -> bool:
	return active() and UNDER.has_point(Vector2(z.x, z.y))


## Whether a step to (x, y) would take `p` from one level to the other where the grid lets it: the ground onto the catwalk beside the mouth, the
## deck into the passage above or below the bridge. The avatar's walking asks it (the tile the middle of its box is in).
func blocks(p, x: float, y: float) -> bool:
	if not active():
		return false
	var c := floori(x)
	var r := floori(y)
	if r == WALK_ROW and ABUTMENTS.has(c):
		return not on_deck(p)
	if PASSAGE_ROWS.has(r) and Gate.MOUTH_COLS.has(c):
		return on_deck(p)
	return false


## The crew's way from where `p` stands to (tx, ty): `Pathfinder.find` over the walking grid, with the passage above and below the bridge shut to a
## walk that has a deck in it (from or to one: a way down off the bridge is a ladder) and the catwalk's tiles beside the mouth shut to a walk on the
## ground. Without an avatar, and for a goal that cannot be reached that way, exactly `Pathfinder.find`.
func find_path(p, tx: float, ty: float) -> Array:
	var grid: PackedByteArray = sim.world.solid_p
	if not active():
		return sim.path_p.find(grid, p.x, p.y, tx, ty)
	var deck_walk: bool = on_deck(p) or sim.world.on_deck(tx, ty)
	var shut: Array = []
	var cols: Array = Gate.MOUTH_COLS if deck_walk else ABUTMENTS
	var rows: Array = PASSAGE_ROWS if deck_walk else [WALK_ROW]
	for r in rows:
		for c in cols:
			var i: int = int(r) * int(sim.W) + int(c)
			if grid[i] == 0:
				shut.append(i)
	if shut.is_empty():
		return sim.path_p.find(grid, p.x, p.y, tx, ty)
	# (the search's own grid, and the copy of the walking grid that the way is then drawn straight over: both have the tiles shut)
	var held: PackedByteArray = grid.duplicate()
	for i in shut:
		sim.path_p.set_solid(int(i), true)
		held[int(i)] = 1
	var out: Array = sim.path_p.find(held, p.x, p.y, tx, ty)
	for i in shut:
		sim.path_p.set_solid(int(i), false)
	if out.is_empty():
		return sim.path_p.find(grid, p.x, p.y, tx, ty)
	return out


## Why a person on one level cannot use something on the other ("" when they can, or when the levels are not kept): a thing at `at` is on the deck if
## the world says the point is.
func why_not(p, at: Vector2, thing: String = "") -> String:
	if not active():
		return ""
	var mine: bool = on_deck(p)
	if mine == sim.world.on_deck(at.x, at.y):
		return ""
	if mine:
		return "Climb down first"
	return "It is up on the wall: use a ladder" if thing == "" else "%s is up on the wall: use a ladder" % thing
