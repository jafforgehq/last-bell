## The shape of the town (One House, TOWNGEN): a district map, a street network that is not a grid, the blocks between the streets and the lots in them, all as pure data
## and a base terrain (grass, sidewalks, asphalt). The buildings are made from the lots by scripts/town/building_gen.gd; TownGen (scripts/town/town_gen.gd) stamps them.
##
## THE STREETS. The town is a square of `size` tiles with a ring of farms and woods round it (`ring` tiles, the "edge" district) and, inside it, an area cut up by a BSP of
## streets: one MAIN AVENUE (6 wide, east to west, through the middle, out to the border on both sides), then streets of 4 that split what is left again and again until the
## blocks are 20 to 40 tiles a side (so the pitch between streets is 24 to 44 and never the same twice): T-junctions everywhere, a street or two that runs out to the border,
## cul-de-sacs with a turning circle cut into the big suburban blocks, alleys between the two rows of terraces in the old town. Every block has a one tile sidewalk ring.
##
## THE DISTRICTS. A coarse Voronoi of seeds (flipped by the seed) over the blocks, the main avenue's blocks forced to "main", then every type is made sure of: suburb,
## oldtown, main, industrial, civic (three blocks at least in a full town: the church with the bell tower, the fire station, the police station, the clinic, the school),
## park; the ring is "edge".
##
## THE LOTS. A block is one or two rows of lots (a row faces its north or its south street; houses always front north or south) filled with what the district builds
## (TownDistricts.MIX), each a lot dictionary:
##   {"id", "rect": Rect2i, "front": "N"|"S", "district", "kind" (a building kind or "pocket", "park", "plaza", "field", "woods", "meadow", "yard"), "plan" (BuildingPlans.plan),
##    "block": index, "street": the name of the road it faces, "number": its number in that street, "start": bool}
## `make` returns {"size", "ring", "roads", "blocks", "lots", "start_lot", "terrain", "district_map", "marks", "avenue", "landmarks", "arrival"}.
##
## THE ARRIVAL (docs/superpowers/specs/2026-10-05-arrival-design.md; towns of 160 tiles and more, `arrival` is {} in a smaller one, which keeps the old start block). The way into the town is
## the end of the main avenue at its west or its east border (at random; the avenue is kept in the middle half of the town). The two blocks that stand beside the avenue at that end are made
## by hand, a strip of 17 to 26 tiles deep each (`_arrival_side`: the strip, a street across the town behind it, the rest of the area cut as ever): on one side the best candidate (the start
## lot: a family home in a lot of 28 x 22 or more with a clear ring) and on the other a house of the middle sort (a lot of 22 x 15 to 17) and a cottage (10 x 8 in a lot of 14 x 13, the rest of
## the strip's depth behind it a pocket of grass and trees), after a few ordinary lots (the base's spawn rule, scripts/town/base_layout.gd, wants a candidate's middle 36 tiles from the
## map's edge, so the first lots can be no candidate: that is why the third is 46 to 54 tiles from the entry). Their lots carry `tier` ("best" | "ok" | "poor") and `clear` (a bare yard
## and ring, like the start lot's). `arrival` = {"east": bool, "ay": the avenue's row, "road": Rect2i of the avenue's end, "pos": the tile the avatar stands on, "face": "E" | "W", "best":
## "N" | "S" the side of the avenue the best candidate is on}.
extends RefCounted

const D := preload("res://scripts/town/town_districts.gd")
const Plans := preload("res://scripts/town/building_plans.gd")

const EDGE := 2
## The smallest and the largest block a street cuts: across (x) and down (y). A block is two rows of lots deep, so it wants 22 to 32 down; along the street it may be longer.
const MIN_BLOCK := 20
const MAX_BLOCK := 56
const MIN_BLOCK_Y := 17
const MAX_BLOCK_Y := 30
const ROAD_W := 4
const AVENUE_W := 6
## The least depth of a row of lots in each district (a block deeper than twice this has two rows).
const DMIN := {"suburb": 13, "oldtown": 10, "main": 10, "industrial": 12, "civic": 12}
## The depth a required building needs for its lot (its depth, the front yard and a back yard).
const NEED_DEPTH := {"church": 22, "school": 22, "supermarket": 19}
## The buildings (lots with one) a full town is topped up to (BIGGER HOUSES: houses are twice the size, so a town has about 115 of them, sheds of some lots counted as houses by the town).
const WANT_BUILDINGS := 115
## The start lot: the family home of 22 x 16 (ROOMY HOUSES) with two or three tiles of ground to each side, three or four in front and three behind. Its block must be this big inside its sidewalk.
const START_W := Plans.START_MIN_W
const START_DEPTH := Plans.START_MIN_DEPTH
## The arrival's blocks (see the header): a town of this size or more has them; the width of the block along the avenue (its sidewalk ring included), the ordinary lots before the
## candidates on the best side and on the other, and the width of the lot of each tier (the house stands in the middle of it).
const ARRIVAL_MIN_SIZE := 160
## (CLEAR3: the block is 60 wide, not 52: the middle sort of house and the cottage of the other side stand ARR_POOR_GAP tiles of open ground apart, so that neither is a neighbour of the other's fence: see FIELD)
const ARR_BLOCK_W := 60
const ARR_POOR_GAP := 8
const ARR_GATE_BEST := 14
## (ROOMY HOUSES: the house of the middle sort is 14 to 16 wide, so its lot is 22 wide: three tiles of ground to each side for the base's fence and the people who work at it; the gate before
## it is two tiles shorter, so that the three lots still fill the block's 50)
const ARR_GATE_OTHER := 14
## (ROOMY HOUSES: the best candidate is the family home of 22 x 16, so its lot is 28 wide and its strip 24 to 26 deep (two tiles of ground to the side, three in front, three behind at the least))
const ARR_BEST_W := 28
const ARR_OK_W := 22
const ARR_POOR_W := 14
const ARR_COTTAGE := Vector2i(10, 8)
const ARR_COTTAGE_GROUND := 5
## EARLY (the walk in is short): the avatar begins this many tiles inside the map's edge, not at it. The avenue's end from the edge to here is the FOREST LANE: the lots on both sides of it (the ring's) are woods for
## ARR_WOODS tiles along it, so that she comes out of the trees. The spawns of a base are still the avenue's asphalt at the edge (35 tiles from a candidate's middle: the candidates have not moved), the lane is that road.
const ARR_ENTRY_IN := 14
const ARR_WOODS := 26
## CLEAR3, THE FIELD OF FIRE. A base's fence ring is the border of its lot (scripts/town/base_layout.gd; the house stands 2 to 4 tiles inside it). Round every candidate's lot there is open ground FIELD tiles
## wide on all sides (`fields`: the lot grown by FIELD, one Rect2i for each candidate): no other building, so that the dead come at the fence across roads, lawns and yards, where they can be seen and shot,
## not through a neighbour's rooms. `_clear_fields` marks every other lot that touches a field (`in_field`); TownGen builds such a lot and, when a building of it would stand in a field, builds it again as a
## vacant one (a meadow or a pocket of grass: no house, a lot of the same size with the same street and number), and then takes the trees, bushes, parked cars and every other tall thing out of the
## fields (scripts/town/town_fields.gd).
const FIELD := 10
const TREES := ["Elm", "Oak", "Birch", "Cedar", "Maple", "Pine", "Ash", "Willow", "Alder", "Hazel", "Linden", "Rowan", "Poplar", "Holly"]
const ROADS_NS := ["Mill Road", "Station Road", "Chapel Lane", "Orchard Road", "School Lane", "Park Road", "Bridge Street", "Garden Way", "Quarry Road", "Field Lane", "Kiln Road", "Hill Road", "Market Lane", "Ferry Road", "Bell Lane", "Tannery Road", "Church Street"]

var rng := RandomNumberGenerator.new()
var size := 192
var ring := 14
var roads: Array = []
var blocks: Array = []
var lots: Array = []
var terrain := PackedInt32Array()
var district_map := PackedByteArray()
var marks: Array = []
var start_lot := -1
var avenue := -1
var landmarks: Array = []
## CLEAR3: the fields of fire (see FIELD): the lot of every candidate grown by FIELD tiles; [] in a town with no arrival.
var fields: Array = []
## The arrival (see the header): {} when the town has none.
var arrival: Dictionary = {}
var _tid := {}
var _area := Rect2i()
var _cul_used := 0


func make(seed_in: int, size_in: int, tids: Dictionary, _opts: Dictionary = {}) -> Dictionary:
	rng.seed = seed_in * 104729 + 31
	size = size_in
	_tid = tids
	ring = clampi(roundi(float(size) * 0.0625), 4, 12)
	_area = Rect2i(ring, ring, size - 2 * ring, size - 2 * ring)
	terrain.resize(size * size)
	terrain.fill(int(_tid.GRASS))
	district_map.resize(size * size)
	district_map.fill(0)
	_roads_and_blocks()
	_districts()
	_cul_de_sacs()
	_paint()
	_ring_lots()
	_block_lots()
	_clear_fields()
	_top_up()
	_names()
	_marks()
	return {"size": size, "ring": ring, "roads": roads, "blocks": blocks, "lots": lots, "start_lot": start_lot, "terrain": terrain, "district_map": district_map,
		"marks": marks, "avenue": avenue, "landmarks": landmarks, "arrival": arrival, "fields": fields}


# ----------------------------------------------------------------- streets, blocks --

func _add_road(dir: String, rect: Rect2i, kind: String, through: bool = false) -> int:
	roads.append({"id": roads.size(), "name": "", "dir": dir, "rect": rect, "kind": kind, "through": through})
	return roads.size() - 1


func _roads_and_blocks() -> void:
	var lo := _area.position.y + MIN_BLOCK_Y
	var hi := _area.end.y - AVENUE_W - MIN_BLOCK_Y
	if hi < lo:
		_bsp(_area, "")
		return
	var with_arrival := size >= ARRIVAL_MIN_SIZE
	# (the arrival's houses want roads 35 to 60 tiles out on every side of them, the base's spawns: the avenue stays in the middle half of the town)
	var ay := lo + int(float(hi - lo) * (rng.randf_range(0.42, 0.58) if with_arrival else rng.randf_range(0.3, 0.7)))
	avenue = _add_road("h", Rect2i(EDGE, ay, size - 2 * EDGE, AVENUE_W), "avenue", true)
	if with_arrival:
		_arrival_blocks(ay)
		return
	_bsp(Rect2i(_area.position.x, _area.position.y, _area.size.x, ay - _area.position.y), "N")
	_bsp(Rect2i(_area.position.x, ay + AVENUE_W, _area.size.x, _area.end.y - ay - AVENUE_W), "S")


## The streets and blocks of a town with an arrival: the avenue's west or east end, and on each side of it a strip of blocks beside the avenue, the first of which is the arrival's block
## (made by hand in `_arrival_lots`); the rest of the two areas is cut as ever.
func _arrival_blocks(ay: int) -> void:
	var east := rng.randf() < 0.5
	var best_north := rng.randf() < 0.5
	var d_best := rng.randi_range(24, 26)
	# (CLEAR3: 19 to 21, not 17 to 19: a medium house is 11 deep with three tiles of ground in front, and the back fence's work spot wants two behind it; at a lot 15 deep the ring row was the
	# house's back wall and the middle sort of house failed the base's check in one town of twelve)
	var d_other := rng.randi_range(19, 21)
	# (EARLY: she begins at the end of the forest lane, ARR_ENTRY_IN tiles in from the edge: the lane is the avenue's end between the border and her)
	arrival = {"east": east, "ay": ay, "best": "N" if best_north else "S",
		"road": Rect2i(size - ARR_ENTRY_IN if east else EDGE, ay, ARR_ENTRY_IN - EDGE, AVENUE_W),
		"pos": Vector2(float(size - ARR_ENTRY_IN) - 0.5 if east else float(ARR_ENTRY_IN) + 0.5, float(ay) + 3.5), "face": "W" if east else "E"}
	_arrival_side("N", Rect2i(_area.position.x, _area.position.y, _area.size.x, ay - _area.position.y), d_best if best_north else d_other, east, best_north)
	_arrival_side("S", Rect2i(_area.position.x, ay + AVENUE_W, _area.size.x, _area.end.y - ay - AVENUE_W), d_other if best_north else d_best, east, not best_north)


## One side of the avenue: the strip beside it (`depth` tiles deep), the street across the town behind the strip, the rest of the area cut as ever (`through` = the side, the street that
## runs out of the town), and the strip itself: the arrival's block at the entry's end, a street, then the rest of the strip cut as ever.
func _arrival_side(side: String, area: Rect2i, depth: int, east: bool, has_best: bool) -> void:
	var strip: Rect2i
	var behind: Rect2i
	var rest: Rect2i
	if side == "N":
		strip = Rect2i(area.position.x, area.end.y - depth, area.size.x, depth)
		behind = Rect2i(area.position.x, strip.position.y - ROAD_W, area.size.x, ROAD_W)
		rest = Rect2i(area.position.x, area.position.y, area.size.x, behind.position.y - area.position.y)
	else:
		strip = Rect2i(area.position.x, area.position.y, area.size.x, depth)
		behind = Rect2i(area.position.x, strip.end.y, area.size.x, ROAD_W)
		rest = Rect2i(area.position.x, behind.end.y, area.size.x, area.end.y - behind.end.y)
	_add_road("h", behind, "street")
	_bsp(rest, side)
	var bx := strip.end.x - ARR_BLOCK_W if east else strip.position.x
	blocks.append({"id": blocks.size(), "rect": Rect2i(bx, strip.position.y, ARR_BLOCK_W, depth), "district": "", "role": "rows", "front_pref": "", "required": [], "cul": true, "start": false,
		"arrival": side, "has_best": has_best})
	var sx := bx - ROAD_W if east else bx + ARR_BLOCK_W
	_add_road("v", Rect2i(sx, strip.position.y, ROAD_W, depth), "street")
	var rest_w := strip.size.x - ARR_BLOCK_W - ROAD_W
	_bsp(Rect2i(strip.position.x if east else sx + ROAD_W, strip.position.y, rest_w, depth), "")


## Splits an area of the town with a street until its pieces are blocks. `through`: "N" or "S" makes the first vertical street run out to that border of the world.
func _bsp(r: Rect2i, through: String) -> void:
	var w := r.size.x
	var h := r.size.y
	var can_v := w >= 2 * MIN_BLOCK + ROAD_W
	var can_h := h >= 2 * MIN_BLOCK_Y + ROAD_W
	var need_v := w > MAX_BLOCK
	var need_h := h > MAX_BLOCK_Y
	var split := true
	if not can_v and not can_h:
		split = false
	elif not need_v and not need_h:
		var roomy := (float(maxi(w - MIN_BLOCK, 0)) / float(MAX_BLOCK - MIN_BLOCK) + float(maxi(h - MIN_BLOCK_Y, 0)) / float(MAX_BLOCK_Y - MIN_BLOCK_Y)) * 0.5
		split = rng.randf() < roomy * 0.75
	if not split:
		blocks.append({"id": blocks.size(), "rect": r, "district": "", "role": "rows", "front_pref": "", "required": [], "cul": false, "start": false})
		return
	var split_v := false
	if can_v and can_h:
		if need_v and not need_h:
			split_v = true
		elif need_h and not need_v:
			split_v = false
		else:
			split_v = float(w) * rng.randf_range(0.6, 1.3) >= float(h)
	else:
		split_v = can_v
	if split_v:
		var c1 := _cut(w, MIN_BLOCK)
		var road := Rect2i(r.position.x + c1, r.position.y, ROAD_W, h)
		var thru := false
		if through == "N":
			road = Rect2i(road.position.x, EDGE, ROAD_W, r.end.y - EDGE)
			thru = true
		elif through == "S":
			road = Rect2i(road.position.x, r.position.y, ROAD_W, size - EDGE - r.position.y)
			thru = true
		_add_road("v", road, "street", thru)
		_bsp(Rect2i(r.position.x, r.position.y, c1, h), "")
		_bsp(Rect2i(r.position.x + c1 + ROAD_W, r.position.y, w - c1 - ROAD_W, h), "")
	else:
		var c1 := _cut(h, MIN_BLOCK_Y)
		_add_road("h", Rect2i(r.position.x, r.position.y + c1, w, ROAD_W), "street")
		_bsp(Rect2i(r.position.x, r.position.y, w, c1), "")
		_bsp(Rect2i(r.position.x, r.position.y + c1 + ROAD_W, w, h - c1 - ROAD_W), "")


## The size of the first block when a length is cut in two by a street: both at least MIN_BLOCK, the middle favoured.
func _cut(length: int, min_block: int) -> int:
	var total := length - ROAD_W
	var lo := min_block
	var hi := total - min_block
	return lo + int(roundf(float(hi - lo) * rng.randf()))


# ---------------------------------------------------------------------- districts --

func _districts() -> void:
	var av_y := float(_area.size.y) * 0.5
	if avenue >= 0:
		av_y = float(roads[avenue].rect.position.y) + float(AVENUE_W) * 0.5 - float(_area.position.y)
	var v_av := av_y / float(_area.size.y)
	var fx := rng.randf() < 0.5
	var fy := rng.randf() < 0.5
	var seeds: Array = [
		["suburb", 0.86, 0.14, 0.9], ["suburb", 0.1, 0.12, 0.8], ["suburb", 0.72, 0.82, 1.1], ["suburb", 0.28, 0.9, 0.7],
		["oldtown", 0.3, 0.36, 1.3], ["oldtown", 0.46, 0.8, 1.3], ["oldtown", 0.66, 0.3, 1.3], ["oldtown", 0.1, 0.55, 1.2], ["oldtown", 0.86, 0.5, 0.9],
		["civic", 0.52, 0.2, 1.0], ["civic", 0.16, 0.68, 0.9],
		["industrial", 0.92, 0.55, 1.3],
		["park", 0.6, 0.64, 0.7],
	]
	for s in seeds:
		if fx:
			s[1] = 1.0 - float(s[1])
		if fy:
			s[2] = 1.0 - float(s[2])
		s[1] = float(s[1]) + rng.randf_range(-0.05, 0.05)
		s[2] = float(s[2]) + rng.randf_range(-0.05, 0.05)
	for u in [0.34, 0.5, 0.66]:
		seeds.append(["main", u, v_av, 1.6])
	for b in blocks:
		var r: Rect2i = b.rect
		var u := (float(r.position.x) + float(r.size.x) * 0.5 - float(_area.position.x)) / float(_area.size.x)
		var v := (float(r.position.y) + float(r.size.y) * 0.5 - float(_area.position.y)) / float(_area.size.y)
		var best := 1.0e9
		var kind := "suburb"
		for s in seeds:
			var du: float = u - float(s[1])
			var dv: float = v - float(s[2])
			var dd := (du * du + dv * dv) / float(s[3])
			if dd < best:
				best = dd
				kind = String(s[0])
		b.district = kind
		b["u"] = u
		b["v"] = v
		if avenue >= 0:
			var ar: Rect2i = roads[avenue].rect
			if r.end.y == ar.position.y:
				b.front_pref = "S"
			elif r.position.y == ar.end.y:
				b.front_pref = "N"
			if b.front_pref != "" and u > 0.18 and u < 0.82:
				b.district = D.MAIN
	# the arrival's blocks are houses (`_arrival_lots` makes their lots)
	for b in blocks:
		if String(b.get("arrival", "")) != "":
			b.district = D.SUBURB
	# one park (the smallest of the blocks the seed gave it), the rest houses
	var parks: Array = []
	for b in blocks:
		if b.district == D.PARK:
			parks.append(b)
	parks.sort_custom(func(a, b): return Rect2i(a.rect).get_area() < Rect2i(b.rect).get_area())
	for i in range(1, parks.size()):
		parks[i].district = D.SUBURB
	# (a park is not more than about 30 x 30: a bigger block the seed gave it is houses and the park is the smallest block that will do)
	if not parks.is_empty() and Rect2i(parks[0].rect).get_area() > 1000:
		parks[0].district = D.SUBURB
	_ensure(D.MAIN, 0.5, v_av, 2)
	if size >= 128:
		_ensure(D.CIVIC, 0.5, v_av + (-0.2 if not fy else 0.2), 3)
		_ensure(D.OLDTOWN, 0.35, 0.45, 2)
		_ensure(D.INDUSTRIAL, 0.9, 0.9, 1)
		_ensure(D.PARK, 0.6, 0.62, 1)
		_ensure(D.SUBURB, 0.75, 0.8, 4)
	else:
		_ensure(D.SUBURB, 0.7, 0.7, 1)
		_ensure(D.OLDTOWN, 0.3, 0.4, 1)
	# the park blocks are parks
	for b in blocks:
		if b.district == D.PARK:
			b.role = "park"
	# the start block: the suburban block with room for the start lot nearest the middle of the town and farthest from the shops and the works
	var best_score := 1.0e9
	var pick := -1
	if not arrival.is_empty():
		# (a town with an arrival: the start lot is the best candidate, in the arrival's block on the best side of the avenue)
		for b in blocks:
			if String(b.get("arrival", "")) != "" and bool(b.get("has_best", false)):
				pick = int(b.id)
	for b in blocks:
		if not arrival.is_empty():
			break
		# (a block of the old town or the works will do when no suburban one is placed right: it becomes a suburb)
		if b.district != D.SUBURB and b.district != D.OLDTOWN and b.district != D.INDUSTRIAL:
			continue
		var r: Rect2i = b.rect
		if r.size.y - 2 < 12 or r.size.x - 2 < 16:
			continue
		var c := Vector2(r.get_center())
		var near_busy := 60.0
		for o in blocks:
			if o.district == D.MAIN or o.district == D.INDUSTRIAL:
				near_busy = minf(near_busy, c.distance_to(Vector2(Rect2i(o.rect).get_center())))
		# near the middle of the town (within 45 tiles) and at least 28 tiles from the shops and the works, if there is such a block
		var to_mid := c.distance_to(Vector2(float(size) * 0.5, float(size) * 0.5))
		var score := to_mid * 0.3 + maxf(0.0, to_mid - 45.0) * 1.5 + maxf(0.0, 28.0 - near_busy) * 1.5 + (0.0 if b.district == D.SUBURB else 30.0)
		# (the family home of the start with its yard wants START_W x START_DEPTH inside the sidewalk: a block too small for it is the last choice)
		if r.size.y - 2 < START_DEPTH or r.size.x - 2 < START_W:
			score += 400.0
		# (the base wants roads 35 to 60 tiles out on all four sides of it: a start near the world's edge has none on that side)
		var edge_room := minf(minf(c.x, float(size) - c.x), minf(c.y, float(size) - c.y))
		if edge_room < float(ring) + 36.0 and size >= 160:
			score += 200.0 + (float(ring) + 36.0 - edge_room) * 4.0
		if score < best_score:
			best_score = score
			pick = int(b.id)
	if pick < 0:
		for b in blocks:
			if Rect2i(b.rect).size.y - 2 >= 12 and Rect2i(b.rect).size.x - 2 >= 16 and b.district != D.PARK:
				pick = int(b.id)
				b.district = D.SUBURB
				break
	if pick >= 0:
		blocks[pick].start = true
		blocks[pick].district = D.SUBURB
		blocks[pick].cul = true    # (the start block keeps its streets: no cul-de-sac cut into it)
	# the civic blocks: the church (the smallest block deep enough for it), the school (the same), and one more with the fire station, the police station and the clinic; the
	# other blocks of the district are houses (a civic block is a lot of ground for a few buildings)
	var civic: Array = []
	for b in blocks:
		if b.district == D.CIVIC:
			civic.append(b)
	civic.sort_custom(func(a, b): return Rect2i(a.rect).get_area() < Rect2i(b.rect).get_area())
	var church_b: Dictionary = {}
	var school_b: Dictionary = {}
	for b in civic:
		var r: Rect2i = b.rect
		if church_b.is_empty() and r.size.y - 2 >= NEED_DEPTH.church and r.size.x - 2 >= 22:
			church_b = b
		elif school_b.is_empty() and r.size.y - 2 >= NEED_DEPTH.school and r.size.x - 2 >= 26:
			school_b = b
	if church_b.is_empty() and not civic.is_empty():
		church_b = civic[civic.size() - 1]
	if school_b.is_empty() and civic.size() > 1:
		for b in civic:
			if b != church_b:
				school_b = b
	var third: Dictionary = {}
	for b in civic:
		if b != church_b and b != school_b and third.is_empty():
			third = b
		elif b != church_b and b != school_b and not b.start:
			b.district = D.SUBURB if int(b.id) % 2 == 0 else D.OLDTOWN
	if not church_b.is_empty():
		church_b.required = ["church"]
		church_b.role = "single"
	if not school_b.is_empty():
		school_b.required = ["school"]
		school_b.role = "single"
	if not third.is_empty():
		third.required = ["fire_station", "police", "clinic"]
	# one main block is the market, one has the supermarket and its car park (the smallest ones that will do)
	var mains: Array = []
	for b in blocks:
		if b.district == D.MAIN:
			mains.append(b)
	mains.sort_custom(func(a, b): return Rect2i(a.rect).get_area() < Rect2i(b.rect).get_area())
	var made_super := false
	var made_market := false
	for b in mains:
		var r: Rect2i = b.rect
		if not made_super and r.size.y - 2 >= NEED_DEPTH.supermarket and r.size.x - 2 >= 26:
			b.required = ["supermarket"]
			b.role = "single"
			made_super = true
		elif not made_market and r.size.x - 2 >= 20 and r.size.y - 2 >= 14:
			b.required = ["plaza"]
			made_market = true


## Makes sure `count` blocks are of a district: the nearest to the nominal place (unit coordinates) of those that are not the last of their kind are turned.
func _ensure(kind: String, u: float, v: float, count: int) -> void:
	var have := 0
	for b in blocks:
		if b.district == kind:
			have += 1
	var guard := 0
	while have < count and guard < 8:
		guard += 1
		var best := 1.0e9
		var pick := -1
		for b in blocks:
			if b.district == kind or b.start or String(b.get("arrival", "")) != "":
				continue
			var left := 0
			for o in blocks:
				if o.district == b.district:
					left += 1
			if left <= 1 and b.district != "":
				continue
			if kind == D.PARK and (Rect2i(b.rect).size.x < 24 or Rect2i(b.rect).size.y < 24):
				continue
			if kind == D.CIVIC and (b.district == D.MAIN or b.district == D.INDUSTRIAL or b.district == D.PARK or Rect2i(b.rect).size.y < 22):
				continue
			if kind == D.MAIN and b.front_pref == "":
				continue
			var du: float = float(b.u) - u
			var dv: float = float(b.v) - v
			var dd := du * du + dv * dv
			if kind == D.PARK:
				dd += float(Rect2i(b.rect).get_area()) / 30000.0
			if dd < best:
				best = dd
				pick = int(b.id)
		if pick < 0:
			return
		blocks[pick].district = kind
		have += 1


# ---------------------------------------------------------------- cul-de-sacs, alleys --

func _cul_de_sacs() -> void:
	var out: Array = []
	for b in blocks:
		var r: Rect2i = b.rect
		if b.district != D.PARK and b.district != D.CIVIC and String(b.role) == "rows" and String(b.front_pref) == "" and _cul_used < 7 and not b.cul and r.size.x >= 28 and r.size.y >= 34 and rng.randf() < 0.85:
			_cul_used += 1
			var west := rng.randf() < 0.5
			var lo := r.position.y + 14
			var hi := r.end.y - 6 - 14
			var sy := rng.randi_range(lo, maxi(lo, hi))
			var len := r.size.x - 9
			var x0 := r.position.x if west else r.end.x - len
			var road_i := _add_road("h", Rect2i(x0, sy + 1, len, 4), "cul")
			var cx := float(r.position.x + len) if west else float(r.end.x - len)
			roads[road_i]["circle"] = Vector2(cx, float(sy) + 3.0)
			# beyond the circle, to the block's far edge: the strip and the street's end column
			if west:
				roads[road_i]["strip"] = Rect2i(int(cx) + 3, sy, r.end.x - int(cx) - 3, 6)
				roads[road_i]["strip_edge"] = r.end.x - 1
			else:
				roads[road_i]["strip"] = Rect2i(r.position.x, sy, int(cx) - 3 - r.position.x, 6)
				roads[road_i]["strip_edge"] = r.position.x
			var n := {"id": 0, "rect": Rect2i(r.position.x, r.position.y, r.size.x, sy - r.position.y), "district": b.district, "role": "rows", "front_pref": "S", "required": [], "cul": true, "start": false, "u": b.u, "v": b.v}
			var s := {"id": 0, "rect": Rect2i(r.position.x, sy + 6, r.size.x, r.end.y - sy - 6), "district": b.district, "role": "rows", "front_pref": "N", "required": [], "cul": true, "start": false, "u": b.u, "v": b.v}
			out.append(n)
			out.append(s)
			landmarks.append({"kind": "cul_de_sac", "pos": Vector2(cx, float(sy) + 3.0)})
		else:
			out.append(b)
	blocks = out
	for i in blocks.size():
		blocks[i].id = i


# ----------------------------------------------------------------------------- paint --

func _tile(x: int, y: int, name: String) -> void:
	if x >= 0 and y >= 0 and x < size and y < size:
		terrain[y * size + x] = int(_tid[name])


func _fill(r: Rect2i, name: String) -> void:
	var c := r.intersection(Rect2i(0, 0, size, size))
	var id := int(_tid[name])
	for y in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			terrain[y * size + x] = id


func _mark_district(r: Rect2i, d: String) -> void:
	var c := r.intersection(Rect2i(0, 0, size, size))
	var v := D.ALL.find(d) + 1
	for y in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			district_map[y * size + x] = v


func _paint() -> void:
	_mark_district(Rect2i(0, 0, size, size), D.EDGE)
	for b in blocks:
		var r: Rect2i = b.rect
		_fill(r, "SIDEWALK")
		_fill(r.grow(-1), "GRASS")
		_mark_district(r, String(b.district))
	for rd in roads:
		var r: Rect2i = rd.rect
		match String(rd.kind):
			"alley":
				_fill(r, "CONCRETE")
			"cul":
				_fill(r, "ASPHALT")
				var c: Vector2 = rd.circle
				for y in range(int(c.y) - 4, int(c.y) + 5):
					for x in range(int(c.x) - 4, int(c.x) + 5):
						if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c) <= 3.2:
							_tile(x, y, "ASPHALT")
			_:
				_fill(r, "ASPHALT")
	# (the streets belong to no district: 0 in the district map)
	for rd in roads:
		if String(rd.kind) == "alley":
			continue
		var rr: Rect2i = rd.rect
		for y in range(maxi(0, rr.position.y), mini(size, rr.end.y)):
			for x in range(maxi(0, rr.position.x), mini(size, rr.end.x)):
				district_map[y * size + x] = 0
	# the strip beyond a cul-de-sac's circle: a sidewalk along the street at its end, grass between (the six rows round the street are not in any block)
	for rd in roads:
		if String(rd.kind) != "cul":
			continue
		var strip: Rect2i = rd["strip"]
		_fill(strip, "GRASS")
		var edge_x: int = int(rd["strip_edge"])
		for y in range(strip.position.y, strip.end.y):
			_tile(edge_x, y, "SIDEWALK")


func _marks() -> void:
	for rd in roads:
		var r: Rect2i = rd.rect
		var k := String(rd.kind)
		if k == "alley":
			continue
		var horiz := String(rd.dir) == "h"
		var gaps: Array = []
		for o in roads:
			if o.id == rd.id or String(o.dir) == String(rd.dir) or String(o.kind) == "alley":
				continue
			var q: Rect2i = o.rect
			if r.grow(1).intersects(q):
				gaps.append([float(q.position.x) if horiz else float(q.position.y), float(q.end.x) if horiz else float(q.end.y)])
		var w := float(r.size.x) if horiz else float(r.size.y)
		var h := float(r.size.y) if horiz else float(r.size.x)
		var cx := float(r.position.x) + float(r.size.x) / 2.0
		var cy := float(r.position.y) + float(r.size.y) / 2.0
		marks.append({"kind": "lanes", "cx": cx, "cy": cy, "w": w if horiz else h, "h": h if horiz else w, "dir": "h" if horiz else "v", "gaps": gaps, "seed": 1000 + int(rd.id)})


# --------------------------------------------------------------------------- the ring --

## The farms, fields and woods round the town: lots along the four strips of the ring, cut where a street runs out through them.
func _ring_lots() -> void:
	var depth := ring - EDGE
	if depth < 3:
		return
	var strips: Array = [
		[Rect2i(EDGE, EDGE, size - 2 * EDGE, depth), "h", "S"],
		[Rect2i(EDGE, size - ring, size - 2 * EDGE, depth), "h", "N"],
		[Rect2i(EDGE, ring, depth, size - 2 * ring), "v", ""],
		[Rect2i(size - ring, ring, depth, size - 2 * ring), "v", ""],
	]
	var cutters: Array = []
	for rd in roads:
		if bool(rd.through):
			cutters.append(Rect2i(rd.rect).grow(1))
	# EARLY: the strip the forest lane runs through (the west one, or the east): its lots beside the avenue are woods
	var lane_strip := (3 if bool(arrival.get("east", false)) else 2) if not arrival.is_empty() else -1
	var lane_y := int(arrival.get("ay", -100)) if not arrival.is_empty() else -100
	for si in strips.size():
		var s = strips[si]
		var sr: Rect2i = s[0]
		var horiz: bool = String(s[1]) == "h"
		var a0 := sr.position.x if horiz else sr.position.y
		var a1 := sr.end.x if horiz else sr.end.y
		# the segments between the streets that run through
		var cuts: Array = []
		for c in cutters:
			var cr: Rect2i = c
			if cr.intersects(sr):
				cuts.append([cr.position.x if horiz else cr.position.y, cr.end.x if horiz else cr.end.y])
		cuts.sort_custom(func(p, q): return p[0] < q[0])
		var segs: Array = []
		var at := a0
		for c in cuts:
			if int(c[0]) > at:
				segs.append([at, int(c[0])])
			at = maxi(at, int(c[1]))
		if a1 > at:
			segs.append([at, a1])
		for sg in segs:
			var lo := int(sg[0])
			var hi := int(sg[1])
			if si == lane_strip and hi - lo >= 8 and (hi == lane_y - 1 or lo == lane_y + AVENUE_W + 1):
				# (the forest lane: the woods run ARR_WOODS tiles along the avenue from where it is, and what is left of the segment is as any other)
				var wl := mini(ARR_WOODS, hi - lo)
				if hi - lo - wl < 8:
					wl = hi - lo
				var woods := Rect2i(sr.position.x, hi - wl if hi == lane_y - 1 else lo, sr.size.x, wl)
				_add_lot(woods, "S", D.EDGE, "woods", -1, woods.size.y)
				if hi == lane_y - 1:
					hi -= wl
				else:
					lo += wl
			_ring_segment(sr, horiz, lo, hi, String(s[2]), depth)


func _ring_segment(sr: Rect2i, horiz: bool, a0: int, a1: int, front_h: String, depth: int) -> void:
	var at := a0
	var last := ""
	var farms := 0
	while a1 - at >= 8:
		var rem := a1 - at
		var kind := "field"
		var r := rng.randf()
		if rem >= 30 and depth >= 10 and last != "farm" and r < 0.3:
			kind = "farm"
		elif rem >= 16 and depth >= 9 and r < 0.8:
			kind = "cottage"
		elif r < 0.9 and last != "woods":
			kind = "woods"
		elif r < 0.95:
			kind = "meadow"
		var len := mini(rem, rng.randi_range(18, 28) if kind != "farm" else rng.randi_range(30, 38))
		if kind == "cottage":
			len = mini(rem, rng.randi_range(16, 22))
		if rem - len < 10:
			len = rem
		last = kind
		if kind == "farm" or kind == "cottage":
			farms += 1
			# the farmhouse, the barn and the field of a farm, side by side (a cottage: a small house and its plot)
			var house_len := mini(len, 18 if kind == "farm" else 14)
			var barn_len := mini(len - house_len, 16) if kind == "farm" else 0
			var pos := at
			var house_kind := "farmhouse" if kind == "farm" else ("farmhouse" if rng.randf() < 0.92 else "cottage")
			var tail := "field" if kind == "farm" else ("meadow" if rng.randf() < 0.5 else "field")
			for part in [[house_kind, house_len], ["barn", barn_len], [tail, len - house_len - barn_len]]:
				var l: int = int(part[1])
				if l < 6:
					pos += l
					continue
				var rect := Rect2i(pos, sr.position.y, l, sr.size.y) if horiz else Rect2i(sr.position.x, pos, sr.size.x, l)
				var front := front_h if front_h != "" else ("S" if rng.randf() < 0.5 else "N")
				_add_lot(rect, front, D.EDGE, String(part[0]), -1, rect.size.y if horiz else rect.size.y)
				pos += l
		else:
			var rect := Rect2i(at, sr.position.y, len, sr.size.y) if horiz else Rect2i(sr.position.x, at, sr.size.x, len)
			_add_lot(rect, front_h if front_h != "" else "S", D.EDGE, kind, -1, rect.size.y)
		at += len


# ------------------------------------------------------------------------------ lots --

func _add_lot(rect: Rect2i, front: String, district: String, kind: String, block: int, depth: int, plan: Dictionary = {}) -> int:
	var p := plan
	if p.is_empty() and kind != "pocket" and kind != "park" and kind != "plaza" and kind != "field" and kind != "woods" and kind != "meadow":
		p = Plans.plan(kind, rect.size.x, depth, rng)
		if p.is_empty():
			kind = "pocket"
	lots.append({"id": lots.size(), "rect": rect, "front": front, "district": district, "kind": kind, "plan": p, "block": block, "street": "", "number": 0, "start": false})
	return lots.size() - 1


func _block_lots() -> void:
	for b in blocks:
		var r: Rect2i = b.rect
		var d: String = b.district
		var inner := r.grow(-1)
		if inner.size.x < 4 or inner.size.y < 4:
			continue
		if String(b.role) == "park":
			_add_lot(inner, "N", d, "park", int(b.id), inner.size.y)
			continue
		if String(b.get("arrival", "")) != "":
			_arrival_lots(b, inner)
			continue
		var single := String(b.role) == "single"
		var req: Array = (b.required as Array).duplicate()
		var rows := _rows_for(b, inner, single)
		# a block with a required building that is deep enough has it in a row of its own depth and an ordinary row beside it; one that is not gives it the whole depth
		var req_row := 0
		var split_rest := single
		if single and not req.is_empty():
			var need := int(NEED_DEPTH.get(String(req[0]), 0))
			var dmin := int(DMIN.get(d, 12))
			if need > 0 and inner.size.y >= need + dmin + 1:
				var d1 := mini(need + 3, inner.size.y - dmin - 1)
				var f1 := String(b.front_pref)
				if f1 == "":
					f1 = "S" if rng.randf() < 0.5 else "N"
				if f1 == "N":
					rows = [{"rect": Rect2i(inner.position.x, inner.position.y, inner.size.x, d1), "front": "N"}, {"rect": Rect2i(inner.position.x, inner.position.y + d1, inner.size.x, inner.size.y - d1), "front": "S"}]
					req_row = 0
				else:
					rows = [{"rect": Rect2i(inner.position.x, inner.position.y, inner.size.x, inner.size.y - d1), "front": "N"}, {"rect": Rect2i(inner.position.x, inner.position.y + inner.size.y - d1, inner.size.x, d1), "front": "S"}]
					req_row = 1
				split_rest = false
		# the start lot: the first of a row deep enough, in the start block
		var start_done := not bool(b.start)
		var ri := 0
		for row in rows:
			var rrow: Dictionary = row
			var rows_req: Array = []
			if not req.is_empty() and (ri == req_row or not single):
				if single:
					rows_req = req.duplicate()
					req.clear()
				else:
					rows_req.append(req.pop_front())
			var as_start := not start_done and Rect2i(rrow.rect).size.y >= START_DEPTH and Rect2i(rrow.rect).size.x >= START_W
			var placed := _fill_row(b, rrow, rows_req, as_start, split_rest and not rows_req.is_empty())
			if as_start and placed:
				start_done = true
			ri += 1


## The lots of an arrival block (one row beside the avenue), from the end of the town the entry is at: a few ordinary lots (the gate), then the candidates: on the best side the start lot
## (the family home, 24 wide) and on the other side a house of the middle sort (18 wide) and a cottage (14 wide); the rest of the row as any row. A candidate's lot has `tier` and `clear`.
func _arrival_lots(b: Dictionary, inner: Rect2i) -> void:
	var east := bool(arrival.east)
	var front := "S" if String(b.arrival) == "N" else "N"
	var depth := inner.size.y
	var list: Array = [["", ARR_GATE_BEST, ""], ["start", ARR_BEST_W, "best"]] if bool(b.get("has_best", false)) else [["", ARR_GATE_OTHER, ""], ["ok", ARR_OK_W, "ok"], ["gap", ARR_POOR_GAP, ""], ["cottage", ARR_POOR_W, "poor"]]
	var t := 0
	for e in list:
		var w: int = e[1]
		var rect := _arrival_span(inner, east, t, w)
		t += w
		var kind := String(e[0])
		if kind == "gap":
			# (CLEAR3: open ground between the two candidates of this side)
			_add_lot(rect, front, b.district, "pocket", int(b.id), depth)
			continue
		if kind == "ok":
			kind = "medium" if rng.randf() < 0.7 else "small"
		# (the cottage's lot is no deeper than its house and a tile of ground in front and behind: no yard to speak of; the rest of the row's depth behind it is a pocket)
		var lot_depth := mini(depth, ARR_COTTAGE.y + ARR_COTTAGE_GROUND) if kind == "cottage" else depth
		var plan: Dictionary = Plans.plan(kind, w, lot_depth, rng) if kind != "" else {}
		if plan.is_empty():
			# (the gate, or a lot the plan does not fit: an ordinary row there)
			_fill_row(b, {"rect": rect, "front": front}, [], false)
			continue
		if kind == "cottage":
			# (the arrival's cottage is 10 x 8, not 7 x 6 or 7: its three rooms must have room for the base's four props)
			plan["box"] = ARR_COTTAGE
			plan["parts"] = [Rect2i(0, 0, ARR_COTTAGE.x, ARR_COTTAGE.y)]
			if lot_depth < depth:
				var behind := depth - lot_depth
				if front == "N":
					_add_lot(Rect2i(rect.position.x, rect.position.y + lot_depth, w, behind), front, b.district, "pocket", int(b.id), behind)
				else:
					_add_lot(Rect2i(rect.position.x, rect.position.y, w, behind), front, b.district, "pocket", int(b.id), behind)
					rect = Rect2i(rect.position.x, rect.position.y + behind, w, lot_depth)
				rect.size.y = lot_depth
		var id := _add_lot(rect, front, b.district, kind, int(b.id), lot_depth, plan)
		lots[id]["tier"] = String(e[2])
		lots[id]["clear"] = true
		if kind == "start":
			lots[id].start = true
			start_lot = id
	if inner.size.x - t >= 4:
		_fill_row(b, {"rect": _arrival_span(inner, east, t, inner.size.x - t), "front": front}, [], false)


## The rectangle of a lot of an arrival block: `t` tiles from the end of the block the entry is at, `w` wide, the block's whole depth.
func _arrival_span(inner: Rect2i, east: bool, t: int, w: int) -> Rect2i:
	return Rect2i(inner.end.x - t - w if east else inner.position.x + t, inner.position.y, w, inner.size.y)


## The rows of lots in a rectangle of a block: two (a north one facing north, a south one facing south, with an alley between them in the old town) when it is deep enough,
## else one facing the street it prefers (`single`: one row whatever the depth).
func _rows_for(b: Dictionary, area: Rect2i, single: bool) -> Array:
	var d: String = b.district
	var hi := area.size.y
	var dmin := int(DMIN.get(d, 12))
	var rows: Array = []
	if bool(b.start) and not single and hi >= START_DEPTH:
		# the start block: a row of the start lot's depth (a strip of what is left behind it, if that is deep enough to be worth a row, else the start lot has it all)
		var front0 := String(b.front_pref)
		if front0 == "":
			front0 = "S" if rng.randf() < 0.5 else "N"
		var rest := hi - (START_DEPTH + 1)
		var sd := START_DEPTH + 1 if rest >= 4 else hi
		if front0 == "N":
			rows.append({"rect": Rect2i(area.position.x, area.position.y, area.size.x, sd), "front": "N"})
			if rest >= 4:
				rows.append({"rect": Rect2i(area.position.x, area.position.y + sd, area.size.x, hi - sd), "front": "S"})
		else:
			if rest >= 4:
				rows.append({"rect": Rect2i(area.position.x, area.position.y, area.size.x, hi - sd), "front": "N"})
			rows.append({"rect": Rect2i(area.position.x, area.position.y + hi - sd, area.size.x, sd), "front": "S"})
		return rows
	if not single and hi >= 2 * dmin and not (bool(b.start) and hi < 24):
		var alley := 2 if ((d == D.OLDTOWN or d == D.MAIN) and hi >= 2 * dmin + 2) else 0
		var dn := (hi - alley) / 2
		if rng.randf() < 0.5 and hi - alley - dn - 1 >= dmin:
			dn += 1
		rows.append({"rect": Rect2i(area.position.x, area.position.y, area.size.x, dn), "front": "N"})
		rows.append({"rect": Rect2i(area.position.x, area.position.y + dn + alley, area.size.x, hi - dn - alley), "front": "S"})
		if alley > 0:
			var ai := _add_road("h", Rect2i(area.position.x - 1, area.position.y + dn, area.size.x + 2, alley), "alley")
			roads[ai]["name"] = "Back Lane"
	else:
		var front := String(b.front_pref)
		if front == "":
			front = "S" if rng.randf() < 0.5 else "N"
		rows.append({"rect": area, "front": front})
	return rows


## `split_rest`: when the required buildings are placed, the rest of the row (its full depth) is cut into rows of its own.
func _fill_row(b: Dictionary, row: Dictionary, required: Array, as_start: bool, split_rest: bool = false) -> bool:
	var r: Rect2i = row.rect
	var d: String = b.district
	var front: String = row.front
	var depth := r.size.y
	var x := r.position.x
	var x1 := r.end.x
	var need: Array = required.duplicate()
	var guard := 0
	var first := true
	var start_placed := false
	while x1 - x >= 4 and guard < 60:
		guard += 1
		var rem := x1 - x
		if split_rest and need.is_empty() and not first:
			for sub in _rows_for(b, Rect2i(x, r.position.y, rem, depth), false):
				_fill_row(b, sub, [], false, false)
			return start_placed
		var kind := ""
		var plan := {}
		if first and as_start:
			kind = "start"
			plan = Plans.plan("start", rem, depth, rng)
			if plan.is_empty():
				kind = ""
		if kind == "" and not need.is_empty():
			var want := String(need.pop_front())
			if want == "plaza":
				plan = {}
				kind = "plaza"
			else:
				plan = Plans.plan(want, rem, depth, rng)
				kind = want if not plan.is_empty() else ""
		if kind == "" and d == D.SUBURB and rem >= 16 and depth >= 16 and rng.randf() < 0.7:
			# the roomy houses of the suburb (the family home, an L, a T, a U, two wings, a bungalow with its garage) need a wide, deep lot: when the row has the room they are tried first
			var wide := ["family", "family", "family", "family", "family", "lhouse", "twowing", "bungalow", "thouse", "uhouse", "bungalow"]
			for attempt in 3:
				var k2 := String(wide[rng.randi() % wide.size()])
				plan = Plans.plan(k2, rem, depth, rng)
				if not plan.is_empty():
					kind = k2
					break
		if kind == "":
			for attempt in 16:
				var k := String(D.pick(D.MIX.get(d, D.MIX.suburb), rng))
				# (the tiny cottage is the last thing a row is filled with: a few of them in a town)
				if k == "cottage" and attempt < 13:
					continue
				if k == "pocket":
					kind = "pocket"
					break
				plan = Plans.plan(k, rem, depth, rng)
				if not plan.is_empty():
					kind = k
					break
			if kind == "":
				kind = "pocket"
		if kind == "pocket" and rem >= 5 and depth >= 7 and rng.randf() < 0.55:
			# a gap in the row is filled in with a shed (a kiosk in the town)
			var conv := "kiosk" if (d == D.MAIN or d == D.OLDTOWN) else ("shed_lot" if d != D.INDUSTRIAL else "")
			if conv != "":
				var p2 := Plans.plan(conv, rem, depth, rng)
				if not p2.is_empty():
					plan = p2
					kind = String(p2.kind)
		var lot_w := 0
		match kind:
			"pocket":
				lot_w = mini(rem, rng.randi_range(4, 8))
			"plaza":
				lot_w = mini(rem, rng.randi_range(14, 18))
			_:
				var box: Vector2i = plan.box
				lot_w = mini(rem, box.x + int(plan.margin))
				if kind == "start":
					lot_w = mini(rem, box.x + 2 * int(plan.margin))
		if rem - lot_w < 5 and rem - lot_w >= 0 and kind != "start":
			if rem - lot_w <= 6 or kind == "pocket":
				lot_w = rem
		var rect := Rect2i(x, r.position.y, lot_w, depth)
		var id := _add_lot(rect, front, d, kind, int(b.id), depth, plan)
		if kind == "start":
			lots[id].start = true
			start_lot = id
			start_placed = true
		x += lot_w
		first = false
	return start_placed


## CLEAR3: the fields of fire (see FIELD). Every lot with a tier (a candidate) has a field, its lot grown by FIELD tiles; every OTHER lot that touches one is marked `in_field` (it has no fence, and no
## house is added to it by `_top_up`). What is built on it is TownGen's business: a lot whose buildings (the house, a shed, a garage: whatever stands on it) touch a field is built again as a vacant one
## (`TownGen._one_lot`: a meadow, or a pocket in a lot narrower than 10 tiles: grass, a bench or two; `vacated`), and the trees, bushes, parked cars and every other tall thing of the fields are taken out
## after the lots are built (scripts/town/town_fields.gd). A lot that merely touches a field with its yard keeps its house, which stands outside it. Candidates stay as they are, and none of them
## is in another's field (ARR_POOR_GAP, and the avenue between the two sides).
func _clear_fields() -> void:
	fields = []
	for lot in lots:
		if String(lot.get("tier", "")) != "":
			fields.append(Rect2i(lot.rect).grow(FIELD))
	if fields.is_empty():
		return
	for lot in lots:
		if String(lot.get("tier", "")) != "" or bool(lot.start):
			continue
		if in_field(lot.rect):
			lot["in_field"] = true


## Whether a rectangle touches a field of fire (see FIELD).
func in_field(r: Rect2i) -> bool:
	for f in fields:
		if (f as Rect2i).intersects(r):
			return true
	return false


## A town is meant to have about 115 buildings (BIGGER HOUSES: it had 150 of half the size; a share of that in a smaller town): when the dice gave fewer, gaps of the suburbs, the old town and the edge (a pocket, a field, a
## meadow) are filled in with small houses until it has. (CLEAR3: not in a field of fire.)
func _top_up() -> void:
	var target := roundi(float(WANT_BUILDINGS) * float(size * size) / float(192 * 192))
	var have := 0
	var cottages := 0
	var gaps: Array = []
	for lot in lots:
		if not (lot.plan as Dictionary).is_empty():
			have += 1
			if String(lot.kind) == "cottage":
				cottages += 1
		elif String(lot.kind) in ["pocket", "meadow", "field"] and not bool(lot.start) and not bool(lot.get("in_field", false)):
			gaps.append(int(lot.id))
	for i in range(gaps.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = gaps[i]
		gaps[i] = gaps[j]
		gaps[j] = t
	for id in gaps:
		if have >= target:
			break
		var lot: Dictionary = lots[id]
		var r: Rect2i = lot.rect
		if r.size.x < 8 or r.size.y < 9:
			continue
		var depth := r.size.y
		# (BIGGER HOUSES: the gaps are filled with houses that fit them, the farm lots of the edge with a farmhouse; the tiny cottage only now and then, a few of them in a town)
		var order: Array = ["farmhouse"] if String(lot.district) == D.EDGE else (["small", "medium", "terrace"] if rng.randf() < 0.5 else ["medium", "small", "terrace"])
		var kind := ""
		var plan := {}
		for k in order:
			plan = Plans.plan(String(k), r.size.x, depth, rng)
			if not plan.is_empty():
				kind = String(k)
				break
		if plan.is_empty() and cottages < 5:
			plan = Plans.plan("cottage", r.size.x, depth, rng)
			kind = "cottage"
			cottages += 1
		if plan.is_empty():
			continue
		lot.kind = kind
		lot.plan = plan
		have += 1


# ------------------------------------------------------------------------------ names --

func _names() -> void:
	var trees := TREES.duplicate()
	var ns := ROADS_NS.duplicate()
	for i in range(trees.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = trees[i]
		trees[i] = trees[j]
		trees[j] = t
	for i in range(ns.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ns[i]
		ns[i] = ns[j]
		ns[j] = t
	var ti := 0
	var ni := 0
	for rd in roads:
		if String(rd.name) != "":
			continue
		match String(rd.kind):
			"avenue":
				rd.name = "Main Street"
			"cul":
				rd.name = "%s Close" % String(trees[ti % trees.size()])
				ti += 1
			"alley":
				rd.name = "Back Lane"
			_:
				if String(rd.dir) == "h":
					rd.name = "%s Street" % String(trees[ti % trees.size()])
					ti += 1
				else:
					rd.name = String(ns[ni % ns.size()])
					ni += 1
	for lot in lots:
		var r: Rect2i = lot.rect
		var front: String = lot.front
		var best := ""
		var best_d := 1000
		for rd in roads:
			if String(rd.kind) == "alley":
				continue
			var q: Rect2i = rd.rect
			if String(rd.dir) != "h":
				continue
			var dist := 1000
			if q.position.x < r.end.x and q.end.x > r.position.x:
				if front == "N":
					dist = absi(r.position.y - q.end.y)
				else:
					dist = absi(q.position.y - r.end.y)
			if dist < best_d:
				best_d = dist
				best = String(rd.name)
		if best == "" or best_d > 6:
			best = "Boundary Road"
		lot.street = best
		lot.number = 2 * (r.position.x / 3) + (0 if front == "N" else 1) + 2
