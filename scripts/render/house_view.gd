## The houses on the screen (One House, WP2), a view part of the town facade (scripts/town/town_game.gd VIEW_PARTS): a roof for each house over its footprint, the
## dark veil of the rooms of the house the avatar is in that are not revealed yet, the doors that swing, and the rule of what is drawn (`pawn_visible`).
##
##  ROOFS. One node (one draw) for each house near the view, over the house's rectangle and a little beyond it (the eaves), above the people (z 7: what is under a roof
##  is hidden by the roof itself). The roof of the house the avatar stands in fades out over FADE seconds and comes back when they leave. A roof is notched at the
##  house's outside doors so that you see where to go in (the doorway is drawn under the people).
##  VEILS. A dark shape for each room of the avatar's house until `clearing.is_revealed(room)` (a missing `clearing` means everything is revealed: no veils).
##  DOORS. A DoorNode for each outside door of a house near the view and for each door of the avatar's house: open while a pawn is within DOOR_R tiles, shut 0.5 s
##  after the last one left; a look-in (a `room_revealed` event while the avatar is a step away from a door of that room) wedges it open until the avatar goes off.
##  WHAT IS DRAWN. `pawn_visible(entity)`: the avatar always; a pawn outside every house, or on a wall or a doorway, always; a pawn in a room of the avatar's house when
##  the room is revealed; a pawn in a room of another house, or in an unrevealed room, never (the facade also keeps its bubble and its bracket away).
##
## COST. Nodes exist only for houses within NEAR tiles of the view (freed beyond FAR), the doors inside a house only for the avatar's house; the scan is a few times a
## second; a frame does no allocation (the pawn positions go in a reused array, a roof fades by its node's alpha, a door redraws only while it swings).
## WP9: a roof is ONE draw call (its pictures are cut from one atlas per roof kit, scripts/render/roof_atlas.gd, so the cells batch), and the furniture and floor marks of a
## house are hidden (not drawn) while its roof is shut: under a roof nobody sees them, and in the street at the default zoom they were two thirds of the sprites drawn.
## Sources: the sim's `houses` (queries of plan 2.2; its `town` Dictionary gives the lists and the tile tables), `clearing`, `search` as the plan says, all soft: a missing
## one is the default (nothing hidden). A test or the demo hands them over with `bind`.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const DoorNode := preload("res://scripts/render/door_node.gd")
const RoomVeil := preload("res://scripts/render/room_veil.gd")
const RoofAtlas := preload("res://scripts/render/roof_atlas.gd")
const RoofPaint := preload("res://scripts/render/roof_paint.gd")

const TILE := GD.TILE
const FADE := 0.25
## How far past the walls the eaves reach, in tiles.
const EAVE := 0.25
## Houses within NEAR tiles of the view get their nodes, and keep them until they are farther than FAR.
const NEAR := 8.0
const FAR := 24.0
const SCAN_EVERY := 0.25
const NEAR_EVERY := 0.1
const DOOR_R := 1.6
## A reveal made when the avatar is this far (tiles) from the door, and no farther than PEEK_MAX, is a look in: the door is wedged open.
const PEEK_MIN := 1.0
const PEEK_MAX := 2.6
const WEDGE_OFF := 7.0
const OUTLINE := Color("221a13")

var sim
var houses
var clearing
var search
var avatar_house := -1
var avatar_room := -1
## The title screen's house (scripts/town/title_scene.gd): shown open, as the house the avatar is in is (its roof gone, its rooms seen, its people drawn), though nobody is the avatar there. -1: none.
var showcase := -1

var _town: Dictionary = {}
var _list: Array = []
var _tile_house := PackedInt32Array()
var _tile_room := PackedInt32Array()
var _w := 0
var _view := Rect2()
var _avatar = null
var _avatar_at := Vector2.ZERO
var _roofs := {}
var _veils := {}
var _doors := {}
var _roof_layer: Node2D
var _veil_layer: Node2D
var _door_layer: Node2D
var _scan_t := 0.0
var _near_t := 0.0
var _shown_house := -2
var _night := 0.0
var _pawns := PackedVector2Array()
var _atlas = null
## The sprites of the world's floor-mark and furniture layers by the house they are in (house id -> Array of nodes), and the houses whose sprites are shown now.
var _interior := {}
var _interior_on := {}


func _init() -> void:
	z_index = 5
	_door_layer = Node2D.new()
	_door_layer.name = "Doors"
	add_child(_door_layer)
	_veil_layer = Node2D.new()
	_veil_layer.name = "Veils"
	add_child(_veil_layer)
	_roof_layer = Node2D.new()
	_roof_layer.name = "Roofs"
	_roof_layer.z_index = 2
	add_child(_roof_layer)


# ---------------------------------------------------------------- the facade's --

## The part is put in the world (above the ground, the doors and veils under the people, the roofs over them) and gets its sources from the sim.
func on_ready(main) -> void:
	var world = main.get("world")
	if world != null and get_parent() == null:
		world.add_child(self)
	var s = main.get("sim")
	bind(s, s.get("houses"), s.get("clearing"), s.get("search"))
	# (WORLD3: in a game the atlas is made by a part of its own, scripts/render/roof_warm.gd, in a frame of its own; the title and a test make it here)
	var town = main.get("town")
	if town == null or bool(town.title) or town.part("roof_warm") == null:
		_warm_atlas()
	_collect_interiors(world)


## The facade tells the view's rectangle before it asks `pawn_visible` of each pawn: the avatar's house is refreshed here, so the rule is never a frame late.
func on_sync_views(view: Rect2) -> void:
	_view = view
	if houses != null and sim != null:
		_find_avatar()


## One frame (`dt` is the frame's real seconds).
func on_frame(dt: float) -> void:
	if houses == null:
		return
	_find_avatar()
	_hide_shut_interiors()
	if avatar_house != _shown_house:
		_shown_house = avatar_house
		_enter_house()
		_scan_t = 0.0
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		_scan()
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = NEAR_EVERY
		_night = _night_of(float(sim.hour)) if sim.get("hour") != null else 0.0
		_measure_doors()
	for h in _roofs:
		var r = _roofs[h]
		if r.modulate.a != r.alpha_t:
			r.tick(dt)
	for room in _veils:
		var v = _veils[room]
		v.set_night(_night)
		v.set_revealed(_revealed(int(room)))
		v.tick(dt)
	for k in _doors:
		var d = _doors[k]
		d.tick(dt, d.near_now)


func on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) != "room_revealed":
		return
	var room := int(e.get("room", -1))
	for k in _doors:
		var d = _doors[k]
		if d.room_a != room and d.room_b != room:
			continue
		var gap: float = (d.center - _avatar_at).length()
		if gap > PEEK_MIN and gap < PEEK_MAX:
			d.wedged = true


## Whether the pawn (a Person or a Zombie) is drawn: see the header.
func pawn_visible(e) -> bool:
	if e == _avatar:
		return true
	var tx := floori(e.x)
	var ty := floori(e.y)
	var h := _house_of(tx, ty)
	if h < 0:
		return true
	var r := _room_of(tx, ty)
	if r < 0:
		return true
	return h == avatar_house and _revealed(r)


# ------------------------------------------------------------------- the sources --

## Hands the part its sources: the sim (people, zombies, avatar), the houses registry, the clearing and search modules (null: everything revealed, nothing looted).
func bind(the_sim, the_houses, the_clearing = null, the_search = null) -> void:
	sim = the_sim
	houses = the_houses
	clearing = the_clearing
	search = the_search
	_town = {}
	_list = []
	_tile_house = PackedInt32Array()
	_tile_room = PackedInt32Array()
	if houses == null:
		return
	var t = houses.get("town")
	if t is Dictionary and not t.is_empty():
		_town = t
		_list = t.houses
		_tile_house = t.tile_house
		_tile_room = t.tile_room
		_w = int(t.size.x)
	else:
		var i := 0
		while true:
			var h = houses.house(i)
			if not (h is Dictionary) or h.is_empty():
				break
			_list.append(h)
			i += 1


func _house_of(tx: int, ty: int) -> int:
	if not _tile_house.is_empty():
		var i := ty * _w + tx
		return _tile_house[i] if tx >= 0 and ty >= 0 and tx < _w and i < _tile_house.size() else -1
	return houses.house_at(float(tx) + 0.5, float(ty) + 0.5)


func _room_of(tx: int, ty: int) -> int:
	if not _tile_room.is_empty():
		var i := ty * _w + tx
		return _tile_room[i] if tx >= 0 and ty >= 0 and tx < _w and i < _tile_room.size() else -1
	return houses.room_at(float(tx) + 0.5, float(ty) + 0.5)


func _revealed(room: int) -> bool:
	return clearing == null or room == avatar_room or (showcase >= 0 and avatar_house == showcase) or clearing.is_revealed(room)


func _find_avatar() -> void:
	var av = null
	var module = sim.get("avatar")
	if module != null:
		av = module.player()
	_avatar = av
	if av == null:
		avatar_house = showcase
		avatar_room = -1
		return
	_avatar_at = Vector2(av.x, av.y)
	var tx := floori(av.x)
	var ty := floori(av.y)
	avatar_house = _house_of(tx, ty)
	avatar_room = _room_of(tx, ty)


# ------------------------------------------------------------------- the nodes --

func _region() -> Rect2:
	if _view.has_area():
		return _view.grow(NEAR)
	return Rect2(_avatar_at - Vector2(30, 30), Vector2(60, 60))


## Makes the nodes of the houses near the view and frees those that are far.
func _scan() -> void:
	var near := _region()
	var far := near.grow(FAR - NEAR)
	for hd in _list:
		var id := int(hd.id)
		var rect := Rect2(hd.rect)
		if near.intersects(rect) or id == avatar_house:
			if not _roofs.has(id):
				_make_roof(hd)
			for i in hd.doors.size():
				if bool(hd.doors[i].exterior) and not _doors.has(id * 64 + i):
					_make_door(hd, i)
		elif not far.intersects(rect):
			_drop_house(id)


func _drop_house(id: int) -> void:
	if _roofs.has(id):
		_roofs[id].queue_free()
		_roofs.erase(id)
	var gone: Array = []
	for k in _doors:
		if int(k) >> 6 == id:
			gone.append(k)
	for k in gone:
		_doors[k].queue_free()
		_doors.erase(k)


## The avatar is in another house (or none): the veils and the inner doors are those of that house, the roofs aim at their targets.
func _enter_house() -> void:
	_show_interior(avatar_house)
	for h in _roofs:
		_roofs[h].alpha_t = 0.0 if int(h) == avatar_house else 1.0
	var gone: Array = []
	for room in _veils:
		if _veils[room].house != avatar_house:
			gone.append(room)
	for room in gone:
		_veils[room].queue_free()
		_veils.erase(room)
	gone.clear()
	for k in _doors:
		var d = _doors[k]
		if not d.exterior and d.house != avatar_house:
			gone.append(k)
		elif d.wedged and d.house != avatar_house:
			d.wedged = false
	for k in gone:
		_doors[k].queue_free()
		_doors.erase(k)
	if avatar_house < 0:
		return
	var hd: Dictionary = _house_dict(avatar_house)
	if hd.is_empty():
		return
	for i in hd.doors.size():
		if not _doors.has(avatar_house * 64 + i):
			_make_door(hd, i)
	if clearing != null:
		for r in hd.rooms:
			if not _veils.has(int(r)):
				var v := RoomVeil.new()
				v.name = "Veil%d" % int(r)
				_veil_layer.add_child(v)
				v.setup(int(r), avatar_house, Rect2i(houses.room(int(r)).rect), _revealed(int(r)))
				var mine: Array = []
				for k in _doors:
					var d = _doors[k]
					if d.house == avatar_house and (d.room_a == int(r) or d.room_b == int(r)):
						mine.append(d)
				v.bind_doors(mine, Callable(self, "_room_lit"))
				_veils[int(r)] = v


## The light of the veils: 0 by day, 1 in the dark of the night, with the dusk and the dawn between.
static func _night_of(hour: float) -> float:
	if hour >= 19.5 or hour < 5.5:
		return 1.0
	if hour >= 17.5:
		return smoothstep(17.5, 19.5, hour)
	if hour < 7.0:
		return 1.0 - smoothstep(5.5, 7.0, hour)
	return 0.0


## Whether the room on the other side of a door is lit (the outside, -1, is), so that its light falls into a dark room.
func _room_lit(r: int) -> bool:
	return r < 0 or _revealed(r)


func _house_dict(id: int) -> Dictionary:
	if id >= 0 and id < _list.size() and int(_list[id].id) == id:
		return _list[id]
	for hd in _list:
		if int(hd.id) == id:
			return hd
	return {}


## The atlas of the roofs, made now (under the loading card) and not at the first roof: `step` 0 the pictures of the kits, 1 the rest (two frames of the card, scripts/render/roof_warm.gd).
func warm_roofs(step: int) -> void:
	if step == 0:
		if _atlas == null:
			_atlas = RoofAtlas.new()
		_atlas.prepare()
	else:
		_warm_atlas()


func _warm_atlas() -> void:
	if _atlas == null:
		_atlas = RoofAtlas.new()
	for kind in TownArt.ROOF_KINDS:
		for variant in 3:
			var tiles = TownArt.roof(String(kind), variant).get("tiles")
			if tiles is Dictionary:
				_atlas.for_tiles(tiles)


func _make_roof(hd: Dictionary) -> void:
	var id := int(hd.id)
	var roof := Roof.new()
	roof.name = "Roof%d" % id
	_roof_layer.add_child(roof)
	var notches: Array = []
	for d in hd.doors:
		if bool(d.exterior):
			notches.append([d.tiles, String(d.side)])
	if _atlas == null:
		_atlas = RoofAtlas.new()
	# (TOWNGEN: a house says which of the kit's roofs it has (`roof` 0 terracotta, 1 slate, 2 shingle) and its `parts`: one roof for each)
	var colour: Dictionary = TownArt.roof("", int(hd.roof)) if hd.has("roof") else TownArt.roof(String(hd.kind), id % 3)
	roof.setup(id, Rect2i(hd.rect), colour, notches, _atlas, hd.parts if hd.has("parts") else [], hd.get("facade", {}), int(hd.roof) if hd.has("roof") else id % 3)
	roof.alpha_t = 0.0 if id == avatar_house else 1.0
	roof.modulate.a = roof.alpha_t
	roof.visible = roof.alpha_t > 0.01
	_roofs[id] = roof


func _make_door(hd: Dictionary, i: int) -> void:
	var door: Dictionary = hd.doors[i]
	var id := int(hd.id)
	var exterior := bool(door.exterior)
	var ns := true
	var inward := Vector2.DOWN
	if exterior:
		var side := String(door.side)
		ns = side == "N" or side == "S"
		inward = {"N": Vector2.DOWN, "S": Vector2.UP, "E": Vector2.LEFT, "W": Vector2.RIGHT}[side]
	else:
		var t: Vector2i = door.tiles[0]
		ns = _room_of(t.x, t.y - 1) >= 0 or _room_of(t.x, t.y + 1) >= 0
		inward = Vector2.DOWN if ns else Vector2.RIGHT
	var n := DoorNode.new()
	n.name = "Door%d_%d" % [id, i]
	_door_layer.add_child(n)
	n.setup(door, ns, inward, id + i)
	n.house = id
	var rooms: Array = []
	for t in door.tiles:
		for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var r := _room_of(t.x + off.x, t.y + off.y)
			if r >= 0 and not rooms.has(r):
				rooms.append(r)
	n.room_a = int(rooms[0]) if rooms.size() > 0 else -1
	n.room_b = int(rooms[1]) if rooms.size() > 1 else -1
	_doors[id * 64 + i] = n


## Who is near a door (the pawns' places are copied into one reused array), and a look-in's wedge is let go when the avatar is off.
func _measure_doors() -> void:
	if _doors.is_empty():
		return
	_pawns.clear()
	# only the pawns the player can see open a door: a dead one in a dark room does not give the room away
	for p in sim.people:
		if not p.dead and p.away == null and pawn_visible(p):
			_pawns.append(Vector2(p.x, p.y))
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying" and pawn_visible(z):
			_pawns.append(Vector2(z.x, z.y))
	var r2 := DOOR_R * DOOR_R
	for k in _doors:
		var d = _doors[k]
		var c: Vector2 = d.center
		var near := false
		for pt in _pawns:
			if (pt - c).length_squared() < r2:
				near = true
				break
		d.near_now = near
		if d.wedged and (d.house != avatar_house or (c - _avatar_at).length() > WEDGE_OFF):
			d.wedged = false


# ------------------------------------------------------------- the interiors --

## Sorts the sprites of the world's floor marks (layer 1) and furniture (layer 2) by the house they stand in, and hides them all: a house is drawn bare under its roof.
## (A world with no `layers`, the tests' fakes, has none: nothing is hidden.)
func _collect_interiors(world) -> void:
	_interior.clear()
	_interior_on.clear()
	if world == null or _tile_house.is_empty() or not (world.get("layers") is Dictionary):
		return
	for key in [1, 2]:
		var layer = world.layers.get(key)
		if layer == null:
			continue
		for n in layer.get_children():
			if not (n is Node2D):
				continue
			var h := _house_of(floori(n.position.x / TILE), floori(n.position.y / TILE))
			if h < 0:
				continue
			if not _interior.has(h):
				_interior[h] = []
			_interior[h].append(n)
			n.visible = false


func _show_interior(h: int) -> void:
	if not _interior.has(h):
		return
	if not _interior_on.has(h):
		_interior_on[h] = true
		for n in _interior[h]:
			n.visible = true


## The sprites of a house the avatar is not in go off when its roof is shut again.
func _hide_shut_interiors() -> void:
	if _interior_on.is_empty():
		return
	var gone: Array = []
	for h in _interior_on:
		if int(h) != avatar_house and roof_alpha(int(h)) >= 0.99:
			gone.append(h)
	for h in gone:
		_interior_on.erase(h)
		for n in _interior[h]:
			n.visible = false


# --------------------------------------------------------------- what tests read --

## The alpha of a house's roof (1.0 when it has none: a roof that is not there is shut).
func roof_alpha(h: int) -> float:
	return _roofs[h].modulate.a if _roofs.has(h) else 1.0


func has_roof(h: int) -> bool:
	return _roofs.has(h)


func veil_count() -> int:
	return _veils.size()


func door_node(h: int, i: int):
	return _doors.get(h * 64 + i)


func veil_of(room: int):
	return _veils.get(room)


## The nodes this part holds (roofs, veils, doors).
func node_count() -> int:
	return _roofs.size() + _veils.size() + _doors.size()


# --------------------------------------------------------------------- the roof --

## One roof, one node drawn once (the fade is the node's alpha). With the art kit's roof tiles: the rectangle's cells in the kit's lit and shade slopes with the ridge cap and
## the eave overlay (the cells of the outside doors are left open, so the doorway shows); without it: a polygon over the rectangle and its eaves with the doorways cut out,
## two halves of a ridge, shingle lines, an outline.
class Roof extends Node2D:
	const TILE_PX := 64.0
	const EAVE_T := 0.25
	const OUTLINE_C := Color("221a13")
	var house := -1
	var alpha_t := 1.0
	var _parts: Array = []
	var _lines := PackedVector2Array()
	var _ridge := PackedVector2Array()
	var _edge := PackedVector2Array()
	var _tex: Texture2D = null
	var _uv := PackedVector2Array()
	var _poly := PackedVector2Array()
	var _shadow := PackedVector2Array()
	var _color := Color.WHITE
	var _batches: Array = []
	## The kit's atlas (scripts/render/roof_atlas.gd) when there is one: every cell is then cut from the one texture and the roof is a single batch.
	var _set = null
	## The draw commands of a roof painted from its facade (scripts/render/roof_paint.gd); null for a roof drawn the old ways.
	var _cmds = null

	## `notches`: [[tiles (Vector2i), side], ...] of the outside doors. `atlas`: the part's RoofAtlas (null: the pictures are drawn from their files).
	func setup(id: int, rect: Rect2i, desc: Dictionary, notches: Array, atlas = null, parts: Array = [], facade: Dictionary = {}, kit: int = 0) -> void:
		house = id
		if desc.has("tiles"):
			_set = atlas.for_tiles(desc.tiles) if atlas != null else null
		if desc.has("tiles") and _set != null:
			# (WORLD3: the roof is painted from the building's facade, scripts/render/roof_paint.gd: styles, colours, what stands on it)
			position = Vector2(rect.position) * TILE_PX
			_cmds = RoofPaint.build(id, rect, desc.tiles, _set, notches, parts, facade, kit)
			_poly = PackedVector2Array([Vector2.ZERO])
			queue_redraw()
			return
		if desc.has("tiles") and _setup_tiles(id, rect, desc.tiles, notches, parts):
			return
		var er := Rect2(rect).grow(EAVE_T)
		var e := Rect2(er.position * TILE_PX, er.size * TILE_PX)
		position = e.position
		var size := e.size
		var poly := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), size, Vector2(0, size.y)])
		var cut: Array = []
		for n in notches:
			var lo := Vector2(1.0e9, 1.0e9)
			var hi := Vector2(-1.0e9, -1.0e9)
			for t in n[0]:
				lo = Vector2(minf(lo.x, t.x), minf(lo.y, t.y))
				hi = Vector2(maxf(hi.x, t.x + 1.0), maxf(hi.y, t.y + 1.0))
			var nr := Rect2(lo * TILE_PX, (hi - lo) * TILE_PX)
			var out := (EAVE_T + 0.05) * TILE_PX
			match String(n[1]):
				"N":
					nr = Rect2(nr.position - Vector2(0, out), nr.size + Vector2(0, out))
				"S":
					nr = Rect2(nr.position, nr.size + Vector2(0, out))
				"W":
					nr = Rect2(nr.position - Vector2(out, 0), nr.size + Vector2(out, 0))
				_:
					nr = Rect2(nr.position, nr.size + Vector2(out, 0))
			nr.position -= e.position
			cut.append(nr)
			var np := PackedVector2Array([nr.position, Vector2(nr.end.x, nr.position.y), nr.end, Vector2(nr.position.x, nr.end.y)])
			var res: Array = Geometry2D.clip_polygons(poly, np)
			if not res.is_empty():
				poly = res[0]
		_poly = poly
		_color = desc.color
		_tex = null if bool(desc.placeholder) else _texture(desc)
		if _tex != null:
			var src: Rect2 = desc.rect
			var ts := _tex.get_size()
			if src.size.x <= 0.0:
				src = Rect2(Vector2.ZERO, ts)
			_uv = PackedVector2Array()
			for p in poly:
				_uv.append((src.position + Vector2(p.x / size.x, p.y / size.y) * src.size) / ts)
		else:
			_make_flat(size, cut)
		_edge = poly.duplicate()
		_edge.append(poly[0])
		# the roof's shadow on the ground to its south east (the light is top left, as in the art kit)
		_shadow = PackedVector2Array()
		for p in poly:
			_shadow.append(p + Vector2(5.0, 8.0))
		queue_redraw()

	## The roof from the kit's tiles. False (nothing drawn yet) when a picture it needs will not load.
	func _setup_tiles(id: int, rect: Rect2i, tiles: Dictionary, notches: Array, parts: Array = []) -> bool:
		var lit: Array = tiles.lit
		var shade: Array = tiles.shade
		var ridge: Dictionary = tiles.ridge
		var edge: Dictionary = tiles.edge
		if lit.is_empty() or shade.is_empty() or ridge.is_empty() or edge.is_empty():
			return false
		for d in [lit[0], lit[1], shade[0], shade[1], edge]:
			if TownArt.texture(d) == null:
				return false
		for d in ridge.values():
			if TownArt.texture(d) == null:
				return false
		position = Vector2(rect.position) * TILE_PX
		# TOWNGEN: a building of several parts (an L, a T, a church...) has one roof for each part, all in this one node: every part is a rectangle of cells with its own ridge, and
		# the eave is drawn only where a cell has no roof next to it (the seam between two parts has none). `parts` empty: one part, the whole rectangle.
		var plist: Array = parts if parts.size() > 0 else [rect]
		var open := {}
		for n in notches:
			for t in n[0]:
				open[Vector2i(t.x - rect.position.x, t.y - rect.position.y)] = true
		var cells := {}
		for pr in plist:
			var pq: Rect2i = pr
			for cy in pq.size.y:
				for cx in pq.size.x:
					cells[Vector2i(pq.position.x - rect.position.x + cx, pq.position.y - rect.position.y + cy)] = true
		var groups := {}
		var order: Array = []
		var done := {}
		var cell: Vector2 = edge.cell
		var span := cell / 224.0 * 1.75 * TILE_PX
		for pr in plist:
			var pq: Rect2i = pr
			var ox := pq.position.x - rect.position.x
			var oy := pq.position.y - rect.position.y
			var w := pq.size.x
			var h := pq.size.y
			var wide := w >= h
			for cy in h:
				for cx in w:
					var gc := Vector2i(ox + cx, oy + cy)
					if open.has(gc) or done.has(gc):
						continue
					done[gc] = true
					var slope := (cy if wide else cx) < (((h if wide else w) + 1) >> 1)
					var variant := 1 if posmod(gc.x * 73 + gc.y * 31 + id * 17, 8) == 0 else 0
					var d: Dictionary = (lit if slope else shade)[variant]
					_add(groups, order, d, Rect2(Vector2(gc) * TILE_PX, Vector2(TILE_PX, TILE_PX)), not wide)
			var rows := h if wide else w
			var line := (rows >> 1) - 1 if rows % 2 == 0 else rows >> 1
			var off := 0.5 if rows % 2 == 0 else 0.0
			var cap: Dictionary = ridge.get("h" if wide else "v", ridge.values()[0])
			for i in (w if wide else h):
				var c := Vector2i(ox + i, oy + line) if wide else Vector2i(ox + line, oy + i)
				if open.has(c):
					continue
				var at := Vector2(c) * TILE_PX + (Vector2(0, off * TILE_PX) if wide else Vector2(off * TILE_PX, 0))
				_add(groups, order, cap, Rect2(at, Vector2(TILE_PX, TILE_PX)), false)
		for gc in done:
			var cx: int = gc.x
			var cy: int = gc.y
			var mask := 0
			if not cells.has(Vector2i(cx, cy - 1)) or open.has(Vector2i(cx, cy - 1)):
				mask |= 1
			if not cells.has(Vector2i(cx + 1, cy)) or open.has(Vector2i(cx + 1, cy)):
				mask |= 2
			if not cells.has(Vector2i(cx, cy + 1)) or open.has(Vector2i(cx, cy + 1)):
				mask |= 4
			if not cells.has(Vector2i(cx - 1, cy)) or open.has(Vector2i(cx - 1, cy)):
				mask |= 8
			if mask == 0:
				continue
			var src := Rect2(Rect2(edge.rect).position + Vector2(mask % int(edge.cols), mask / int(edge.cols)) * cell, cell)
			_add(groups, order, edge, Rect2(Vector2(cx, cy) * TILE_PX - Vector2(0.25, 0.25) * TILE_PX, span), false, src)
		_batches = []
		for key in order:
			_batches.append(groups[key])
		_poly = PackedVector2Array([Vector2.ZERO])
		queue_redraw()
		return true

	## Files a draw command under its picture (consecutive commands of one picture are one batch for the renderer).
	func _add(groups: Dictionary, order: Array, d: Dictionary, dst: Rect2, transpose: bool, src: Rect2 = Rect2()) -> void:
		var from: Rect2 = src if src.size.x > 0.0 else Rect2(d.rect)
		var key := "%s|%s" % [d.file, str(transpose)]
		if _set != null:
			key = "atlas|%s" % str(transpose)
			from = RoofAtlas.rect_for(_set, d, from)
		if not groups.has(key):
			groups[key] = {"tex": _set.tex if _set != null else TownArt.texture(d), "dst": [], "src": [], "t": transpose}
			order.append(key)
		groups[key].dst.append(dst)
		groups[key].src.append(from)

	static func _texture(desc: Dictionary) -> Texture2D:
		return TownArt.texture(desc)

	func _make_flat(size: Vector2, cut: Array) -> void:
		var wide := size.x >= size.y
		var mid := size * 0.5
		var halves: Array = []
		if wide:
			halves = [Rect2(0, 0, size.x, mid.y), Rect2(0, mid.y, size.x, mid.y)]
		else:
			halves = [Rect2(0, 0, mid.x, size.y), Rect2(mid.x, 0, mid.x, size.y)]
		var shades := [_color.lightened(0.1), _color.darkened(0.12)]
		for i in 2:
			var h: Rect2 = halves[i]
			var hp := PackedVector2Array([h.position, Vector2(h.end.x, h.position.y), h.end, Vector2(h.position.x, h.end.y)])
			for part in Geometry2D.intersect_polygons(_poly, hp):
				_parts.append([part, shades[i]])
		# the ridge and the shingle courses, kept off the doorways
		var gap := TILE_PX * 0.5
		if wide:
			_ridge = PackedVector2Array([Vector2(TILE_PX * 0.4, mid.y), Vector2(size.x - TILE_PX * 0.4, mid.y)])
			var y := gap
			while y < size.y - gap * 0.5:
				if absf(y - mid.y) > 3.0:
					_add_line(Vector2(TILE_PX * 0.4, y), Vector2(size.x - TILE_PX * 0.4, y), cut)
				y += gap
		else:
			_ridge = PackedVector2Array([Vector2(mid.x, TILE_PX * 0.4), Vector2(mid.x, size.y - TILE_PX * 0.4)])
			var x := gap
			while x < size.x - gap * 0.5:
				if absf(x - mid.x) > 3.0:
					_add_line(Vector2(x, TILE_PX * 0.4), Vector2(x, size.y - TILE_PX * 0.4), cut)
				x += gap

	func _add_line(a: Vector2, b: Vector2, cut: Array) -> void:
		var box := Rect2(a, b - a).abs().grow(2.0)
		for c in cut:
			if box.intersects(Rect2(c).grow(TILE_PX * 0.3)):
				return
		_lines.append(a)
		_lines.append(b)

	func tick(dt: float) -> void:
		modulate.a = move_toward(modulate.a, alpha_t, dt / 0.25)
		visible = modulate.a > 0.01

	func _draw() -> void:
		if _cmds != null:
			var tex: Texture2D = _set.tex
			var c: RoofPaint.Cmds = _cmds
			for i in c.n:
				var k := i * 4
				draw_texture_rect_region(tex, Rect2(c.dst[k], c.dst[k + 1], c.dst[k + 2], c.dst[k + 3]), Rect2(c.src[k], c.src[k + 1], c.src[k + 2], c.src[k + 3]), c.col[i], c.tr[i] != 0)
			return
		if not _batches.is_empty():
			for b in _batches:
				for i in b.dst.size():
					draw_texture_rect_region(b.tex, b.dst[i], b.src[i], Color.WHITE, b.t)
			return
		if _poly.size() < 3:
			return
		draw_colored_polygon(_shadow, Color(0, 0, 0, 0.22))
		if _tex != null:
			draw_colored_polygon(_poly, Color.WHITE, _uv, _tex)
		else:
			for part in _parts:
				draw_colored_polygon(part[0], part[1])
			if _lines.size() >= 2:
				draw_multiline(_lines, Color(0, 0, 0, 0.13), 1.0)
			if _ridge.size() == 2:
				draw_polyline(_ridge, _color.darkened(0.35), 3.0)
		draw_polyline(_edge, OUTLINE_C, 2.0)
