## The town (feature/town-core): ONE BIG OPEN TOWN, 192 x 192 tiles, made from a seed in the schema of assets/data/map.json that World and Sim are built on.
##
## `TownGen.make(seed)` does it in one go; `var g := TownGen.new(); g.begin(seed); while not g.step(8.0): await frame; g.result()` does it a few
## milliseconds a frame (a loading card; about 0.3 s on the desktop and about the same in Chrome's WebAssembly). The same seed always gives the same town (`TownGen.digest`).
## STEPS: `step` returns after one PIECE of work when the budget is spent: the streets, one lot, one fifth of the street furniture, a third of the map's finish, a piece of the people (the
## arrival, one candidate's rescue list, the dead, the result, the base's layout of one candidate made and checked, a piece of the walk from the entry, the lists); none is more than about
## 10 ms on a desktop (a lot nine at most, a candidate's base layout 9). The generator loads no pictures: it reads the size of a prop's picture from assets/data/prop_sizes.json (`GD.tex_size`, made by
## tools/make_prop_sizes.gd; loading a prop's 1000 x 1500 pixel picture was half of the time and made the first lot of each kind a 60 ms step), and the loader loads them after, one at a time
## (scripts/town/town_loader.gd).
##
## LAYOUT (TOWNGEN). The town is a PLACE, not a grid: scripts/town/town_layout.gd makes a district map (suburb, oldtown, main street, industrial, civic, park, and the farms and
## woods of the edge ring), a street network from a BSP (one main avenue 6 wide through the middle, streets of 4 at irregular pitches, T-junctions, streets that run out of the town,
## cul-de-sacs with a turning circle, alleys behind the terraces), the blocks between the streets (each with a one tile sidewalk ring) and the lots in them (a row of lots faces its
## north or its south street, so a house's `front` is always "N" or "S"). scripts/town/building_gen.gd builds each lot on a SMALL LOCAL SiteCanvas (scripts/raid/site_canvas.gd, the
## generator of the raid sites: walls, doors, named rooms, furniture, containers; a canvas of the town's size cannot be used, `SiteCanvas._put` floods the whole canvas twice per
## prop): a house of rectangles of outer walls ("parts": an L, a T, a U, a bungalow and its garage, a church with a tower...), partitioned into rooms with doors, furnished, with a
## yard, a path, a driveway, a fence; shops, flats, a diner, warehouses, a garage, a scrapyard, the church, the fire and police stations, a clinic, a school, farms, sheds. TownGen
## stamps them into the map. A lot with a shed has a second House (the shed: two rooms). Every house has at least two rooms and one exterior door.
## Roofs are NOT in the ground: the view draws one roof per PART of each house (scripts/render/house_view.gd) and hides it when the avatar is inside.
## NEW KEYS (added to the contract below, nothing changed): result "districts" {"names", "map" (a byte per tile: 1 + the index in names, 0 for the streets), "blocks", "area", "ring"},
## "lots" [{"id", "rect", "front", "district", "kind", "block", "street", "house" (or -1), "start"}], "landmarks" [{"kind": "bell_tower"|"supermarket"|"school"|"fire_station"|
## "police"|"clinic"|"market"|"park"|"cul_de_sac", "pos", "house"}]; `streets` "roads" [{"id", "name", "dir": "h"|"v", "rect", "kind": "avenue"|"street"|"cul"|"alley", "through"}],
## "avenue" (index); house "parts", "district" (suburb|oldtown|main|industrial|civic|park|edge), "type" (residential|commercial|industrial|civic|farm|outbuilding), "yard" (= lot),
## "front_yard", "back_yard" (rects), "yard_type" (lawn|garden|bare|overgrown), "wall" (terrain name of its walls), "roof" (0 terracotta, 1 slate, 2 shingle), "state" (intact|ruined|
## burnt), "boarded", "barricaded", "drive" (a rect or empty), "landmark", "street", "number", "main" (false for a shed).
##
## THE RESULT, a Dictionary (tile coordinates everywhere; Rect2i is {position, size}, a Vector2i a tile, a Vector2 a point in tiles):
##   "seed", "version" (1), "size" (Vector2i 192 x 192)
##   "data"        the map in the schema (terrain, solidZ/solidP as Arrays of W*H ints, objects, marks, trees, rooms, spawns...): World.build / Sim.new take it
##   "houses"      [House]   (index == id)
##   "rooms"       [Room]    (index == `room` of the records and of the "tile_room" array)
##   "containers"  [Container]
##   "dead"        [DeadRecord]  (data only: the DormantDead field turns them into real dead near the avatar)
##   "start"       {"house": id, "pos": Vector2, "room": room index, "ring": the start lot's clear ring report}. KEPT FOR WHAT READS IT (ARRIVAL): `house` is the best candidate (the family home of
##                 the start lot) and `pos` is the ENTRY, where the avatar stands outside every house, `room` -1; a town of less than 5 blocks (the title's, the tests') has no arrival: `pos`
##                 is a free tile of the roomiest room of the start house and `room` its index, as ever
##   "entry"       ARRIVAL: {"pos": Vector2 (the tile the avatar stands on: the end of the main avenue at the west or the east border, 4.5 tiles inside the map's edge, on the lane), "face": "E"|"W"
##                 (the way into town), "road": Rect2i (the avenue's end), "label": "Main Street, west end", "sign": Vector2 (the middle one of the three double chevrons painted on the lane, pointing into
##                 the town, or (-1, -1)), "arrows": [Vector2] (all three)}; a wreck and a car stand on the entry road and no roadblock, and no car or wreck of the streets within 26 tiles
##   "candidates"  ARRIVAL: the homes the player may claim as the base, best first: [{"house": id, "kind", "tier": "best"|"ok"|"poor", "label": "Family home. 8 rooms, big yard.", "rooms": int, "yard":
##                 "big"|"small"|"none", "yard_tiles": int (the lot less the walls' footprint), "dist": float (tiles from the entry to the front door), "door": Vector2 (the tile outside the front
##                 door), "walk": int (the length in tiles of the way from the entry to that tile, 4 ways, the walkable ground), "problems": [] (what `BaseLayout.validate` says of the base made
##                 on it: only candidates with none stand), "ring": {"free", "blocked"} (the base's report of the lot's border)}. A town of 160 tiles or more has three: the family home (the start
##                 lot: 8 rooms, 28 x 22 or more of lot, a clear ring), a house of the middle sort (4 to 6 rooms, 22 x 15 to 17) and a cottage (3 rooms, 14 x 13: no yard), 29 to 54 tiles from the
##                 entry; the title's small town has the start house alone. Each has 3 to 5 dead standing in rooms of their own (2 or 3 in the cottage), its containers with loot, a lot ring free of
##                 trees, props, parked cars and marks; no dead in the streets or yards within 20 tiles of the entry or of any candidate
##   "fields"      CLEAR3: [Rect2i], the field of fire of each candidate: its lot grown by 10 tiles (the fence ring is the lot's border). No other building stands in one (a lot whose building would is built as
##                 a meadow or a pocket of grass: `lots[].vacated`) and nothing tall (a tree, a bush, a parked car, a wreck, a stall, a fence...: scripts/town/town_fields.gd takes it out) is on its ground outside
##                 the candidate's own lot; a few low props stand in the vacant lots. `stats.fields` = {"count", "scrubbed": {"trees", "objects", "tiles", "dressed"}, "vacated"}. A town with no arrival has none.
##   "rescue"      [{"house", "pos": Vector2 (where the survivor waits), "room", "ring": 1..3, "dist": from the start house}] 12 candidates, near to far: the list of the start house
##   "rescue_for"  ARRIVAL: {String(house id of a candidate): the rescue list of that house (the shape of `rescue`, 12 near to far from it; none of the candidates is in any list)}; `rescue` is
##                 `rescue_for` of the start house. A house in two lists keeps its survivor's room and spot; its 2 to 5 dead (one in that room) are in `dead` once
##   "data" also carries `shot_low` (PackedByteArray W*H: 1 on the tiles of the LOW solid props, a bed, a sofa, a table, a counter...: shut to walking as ever but a shot, a blow and the dead's eye go over them;
##                 the lists are assets/data/prop_heights.json, scripts/town/prop_heights.gd; the world keeps it as `world.shot_low`, the sim's `clear_shot` and the avatar's `trace` read it)
##   "data" also carries `kit`, what the art kit needs (scripts/town/town_world.gd reads it, all of it optional): "ground" (PackedByteArray W*H: the ground a tile has, an index into
##                 TownArt.GROUNDS + 1, 0 = by the terrain: the floors of the rooms by type, the paths), "wall" (PackedByteArray: the material of a wall top, TownArt.WALL_MATS), "line"
##                 (PackedByteArray: a fence or hedge cell, TownArt.LINES), "windows" ([{"x", "y", "orient": "h"|"v", "state": "intact"|"broken"|"boarded", "variant", "bar"}]), "gates"
##                 ([{"x", "y", "w", "orient"}]), "houses" ([[x, y, w, h] of each house's bounding box, by id]); and each object of the kit has `kit` (the item), `facing` or `orient`,
##                 `variant`, `state` and, inside a house, `in` (the house's id). The kit's furniture, yards and street things are scripts/town/town_kit.gd's.
##   "tile_house"  PackedInt32Array W*H: the id of the house one of whose parts holds the tile (walls and floor), else -1   (which roof to lift, "am I inside?")
##   "tile_room"   PackedInt32Array W*H: the index of the room whose floor holds the tile, else -1 (a wall, a doorway, outside)
##   "streets"     {"pitch": 32, "block": 28, "road": 4 (the old grid's numbers, kept), "names_x": [names of the north-south streets], "names_y": [names of the east-west ones], "roads", "avenue"}
##   "stats"       counts and the milliseconds each phase took
##
##   House      {"id", "kind": "start"|"family"|"medium"|"small"|"terrace"|"shop"|... (the building program, see scripts/town/building_plans.gd; BIGGER HOUSES, ROOMY HOUSES: the start house is a family home of
##               22 x 16 with eight rooms round a two wide hall, the family homes 20 to 22 x 15 to 16, the detached houses 12 to 22 wide with four to eight rooms (a living room 5 x 4 to 8 x 5, a bedroom
##               4 x 3 or 4 x 4 and more, doors two wide but a bathroom's, the furniture along the walls with a lane two tiles wide from door to door), a town of about 95 to 105 houses), "address": "14 Elm Street", "block": Vector2i (x: the block's
##               index), "rect": Rect2i (the bounding box of the outer walls), "parts": [Rect2i] (the rectangles of outer walls that make the footprint: one roof each),
##               "lot": Rect2i, "front": "N"|"S" (the side its front door is on), "fenced": bool, "door": Vector2i (the tile outside the front door),
##               "doors": [Door], "rooms": [room indexes], "containers": [container ids], "dead": [record indexes] (the ones that stand in it at the start)}
##   Door       {"tiles": [Vector2i] (the doorway: no wall, two wide, one for a small interior door), "exterior": bool, "side": "N"|"S"|"E"|"W" (exterior: the wall
##               it is in; interior: "H" when the doorway runs along x, "V" along y), "out": Vector2i (the tile on the outer side, or the one on the first side),
##               "in": Vector2i (the tile on the other side)}
##   Room       {"id": "h17:kitchen", "house": 17, "name": "kitchen", "rect": Rect2i (the floor, the walls not included)}
##   Container  {"id", "house", "room": room index, "pos": Vector2 (where to stand), "at": Vector2 (the furniture's middle), "kind", "loot": {stock: n}, "search_s"}
##   DeadRecord {"pos": Vector2, "kind": "walker"|"runner"|"brute", "state": "still"|"wander", "house": id or -1 (the street), "room": room index or -1
##               (in the yard, or in the street), "group": street group or -1}   ("clear this room/house" = no record of it left alive: dormant_dead.gd counts them)
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Canvas := preload("res://scripts/raid/site_canvas.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const TownKit := preload("res://scripts/town/town_kit.gd")
const TownLayout := preload("res://scripts/town/town_layout.gd")
const BuildingGen := preload("res://scripts/town/building_gen.gd")
const Districts := preload("res://scripts/town/town_districts.gd")
const Streetscape := preload("res://scripts/town/town_streetscape.gd")
const Plans := preload("res://scripts/town/building_plans.gd")
const PropHeights := preload("res://scripts/town/prop_heights.gd")
const BaseLayout := preload("res://scripts/town/base_layout.gd")
const Fields := preload("res://scripts/town/town_fields.gd")

## The size of the full town (6 blocks a side); `make(seed, {"blocks": n})` makes a smaller one (2: 64 x 64, for tests).
const DEFAULT_SIZE := 192
const DEFAULT_BLOCKS := 6
## (The streets are no longer a grid: PITCH is the size of one "block" of `opts.blocks`, the average pitch; see scripts/town/town_layout.gd.)
const PITCH := 32
const BLOCK := 28
const ROAD := 4
const EDGE := 2
const VERSION := 1
## Dead: how many (the owner's 600 to 800), the share that is in or beside the houses, and how many guard each house of the rescue list.
const DEAD_TOTAL := 700
const DEAD_NEAR_HOUSES := 0.6
## How many dead stand in a building at the start, [least, most], by its kind (the houses one to four; the shops, the flats, the works and the civic buildings more).
const DEAD_BY_KIND := {
	"small": [1, 3], "cottage": [1, 2], "medium": [1, 3], "family": [2, 4], "bungalow": [1, 4], "lhouse": [2, 4], "thouse": [2, 4], "uhouse": [2, 5], "twowing": [2, 4], "terrace": [1, 2], "terrace_ext": [1, 3],
	"rowshop": [1, 3], "kiosk": [0, 1], "cornershop": [2, 3], "shop": [2, 4], "pharmacy": [2, 4], "bakery": [2, 4], "hardware": [2, 4], "diner": [3, 5], "bank": [2, 4], "office": [2, 4],
	"apartments": [4, 8], "supermarket": [6, 10], "library": [2, 4], "clinic": [4, 7], "fire_station": [3, 5], "police": [3, 5], "church": [3, 6], "school": [4, 8],
	"warehouse": [5, 9], "garage": [2, 4], "workshop": [2, 4], "scrapyard": [1, 2], "containers": [1, 2], "farmhouse": [1, 3], "barn": [1, 3], "shed": [0, 1],
}
const RESCUE_COUNT := 12

# ------------------------------------------------------------------ the build --

var seed_value := 1
var _size := 192
var _blocks := 6
var _start_block := Vector2i(3, 3)
var _start_house := -1
var _clear_rect := Rect2i()
## ARRIVAL: the lots of the candidates (and the start lot) that are kept clear, and the houses built on the lots that have a `tier`: [{"house", "tier", "lot"}].
var _clear_rects: Array = []
## CLEAR3: the fields of fire of the candidates (the layout's `fields`: scripts/town/town_fields.gd takes the tall things out of them), and what was taken out.
var _fields: Array = []
var _scrubbed: Dictionary = {}
var _tiers: Array = []
## The room the survivor of a house is given (the first time it is asked): house id -> room index. The road sign of the entry: its middle (tiles), (-1, -1) for none.
var _rescue_rooms := {}
var _entry_sign := Vector2(-1.0, -1.0)
var _entry_arrows: Array = []
var opts: Dictionary = {}
var _phase := 0
var _block := 0
## Which piece of the phase after the lots is next (`step`).
var _sub := 0
var _rng := RandomNumberGenerator.new()
var _lay: Dictionary
var _base: Dictionary
var _terrain_types: Dictionary
var _tids := {}
var _terrain := PackedInt32Array()
var _solid := PackedByteArray()
var _objects: Array = []
var _trees: Array = []
var _houses: Array = []
var _rooms: Array = []
var _containers: Array = []
var _rooms_dict := {}
var _marks: Array = []
var _lot_index := 0
## TOWNGEN: the layout (scripts/town/town_layout.gd), the building painter, the house of each lot (-1: none), the landmarks, whether the lot before was fenced.
var _layout: Dictionary = {}
var _builder
var _lot_house: Array = []
var _landmarks: Array = []
var _prev_fenced := false
var _street_cv
var _street_objs := 0
var _ms := {}
var _started := 0
var _result := {}
var _tile_house := PackedInt32Array()
var _tile_room := PackedInt32Array()
## What the art kit needs (see the header: `data.kit`), the kit's toolbox (scripts/town/town_kit.gd), and its own dice for the choices of the art (variants, the dressing of the streets),
## so that the dead, the rescues and the doors do not depend on them.
var _kit_ground := PackedByteArray()
var _kit_wall := PackedByteArray()
var _kit_line := PackedByteArray()
var _windows: Array = []
var _gates: Array = []
var _kit
var _art_rng := RandomNumberGenerator.new()


static func make(seed_value_in: int = 1, opts_in: Dictionary = {}) -> Dictionary:
	var g = new()
	g.begin(seed_value_in, opts_in)
	while not g.step(1.0e9):
		pass
	return g.result()


func begin(seed_in: int, opts_in: Dictionary = {}) -> void:
	seed_value = seed_in
	opts = opts_in
	_phase = 0
	_block = 0
	_sub = 0
	_started = Time.get_ticks_usec()
	_rng.seed = seed_in * 7919 + 17
	_lay = TownKit.layouts()
	_base = GD.load_all()
	_terrain_types = _base.terrainTypes.duplicate(true)
	for k in _lay.terrain:
		_terrain_types[k] = {"id": int(_lay.terrain[k].id), "file": String(_lay.terrain[k].file)}
	for k in _terrain_types:
		_tids[k] = int(_terrain_types[k].id)
	_blocks = clampi(int(opts_in.get("blocks", DEFAULT_BLOCKS)), 2, 6)
	_size = _blocks * PITCH
	_start_block = Vector2i(_blocks / 2, _blocks / 2)
	_start_house = -1
	_clear_rect = Rect2i()
	_clear_rects = []
	_fields = []
	_scrubbed = {}
	_tiers = []
	_rescue_rooms = {}
	_entry_sign = Vector2(-1.0, -1.0)
	_entry_arrows = []
	_pp = {}
	_terrain.resize(_size * _size)
	_terrain.fill(int(_tids.GRASS))
	_solid.resize(_size * _size)
	_kit_ground.resize(_size * _size)
	_kit_ground.fill(0)
	_kit_wall.resize(_size * _size)
	_kit_wall.fill(0)
	_kit_line.resize(_size * _size)
	_kit_line.fill(0)
	_windows = []
	_gates = []
	_art_rng.seed = seed_in * 40503 + 99
	_kit = TownKit.new()
	_kit.setup(_lay, _tids)


## How far along the build is, 0 to 1 (a loading card's bar).
func progress() -> float:
	var n_blocks := float(maxi(1, _layout.lots.size() if _layout.has("lots") else (_size / PITCH) * (_size / PITCH)))
	match _phase:
		0:
			return 0.0
		1:
			return 0.05 + 0.75 * float(_block) / n_blocks
		2:
			return 0.80 + 0.05 * float(_sub) / float(Streetscape.STEPS)
		3:
			return 0.85 + 0.07 * float(_sub) / float(FINISH_STEPS)
		4:
			return 0.92 + 0.07 * float(_sub) / float(PEOPLE_STEPS)
	return 1.0


## The pieces of the phases after the lots (the street furniture's own, the map's indexes', the people's): `step` does one of them at a time, so that none is more than a few milliseconds on a
## desktop (a browser is slower: a step of 20 ms there is a hitch of the loading card's bar).
const FINISH_STEPS := 3
const PEOPLE_STEPS := 7


## Does about `budget_ms` of the work (always at least one piece of it) and says whether the town is done. A piece is the streets, one lot, or one piece of the street furniture, of the map's
## indexes or of the people (each a few milliseconds on a desktop, a lot nine at most).
func step(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while _phase < 5:
		match _phase:
			0:
				_streets()
				_phase = 1
			1:
				_blocks_until(t0, budget_ms)
				if _block >= _layout.lots.size():
					_phase = 2
					_sub = 0
			2:
				_edge_and_furniture(_sub)
				_sub += 1
				if _sub >= Streetscape.STEPS:
					_phase = 3
					_sub = 0
			3:
				_finish_map(_sub)
				_sub += 1
				if _sub >= FINISH_STEPS:
					_phase = 4
					_sub = 0
			4:
				# (a piece of the people may say it is not done, and is asked again: the walk of the arrival, the candidates one at a time)
				if _people(_sub):
					_sub += 1
				if _sub >= PEOPLE_STEPS:
					_phase = 5
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return _phase >= 5


func result() -> Dictionary:
	return _result


func _tick(name: String, t_in: int) -> void:
	_ms[name] = float(_ms.get(name, 0.0)) + float(Time.get_ticks_usec() - t_in) / 1000.0


# --------------------------------------------------------------------- streets --

func _streets() -> void:
	var t0 := Time.get_ticks_usec()
	var lg := TownLayout.new()
	_layout = lg.make(seed_value, _size, _tids, opts)
	_terrain = _layout.terrain
	_marks = _layout.marks
	_fields = _layout.get("fields", [])
	_street_cv = Canvas.new()
	_street_cv.setup(_size, _size, seed_value + 5, _lay.props, _tids, {})
	_street_cv.size_by_table = true
	_builder = BuildingGen.new()
	_builder.setup(_lay.props, _tids, _kit, _size)
	_tick("streets", t0)


# ------------------------------------------------------------------------ lots --

func _blocks_until(t0: int, budget_ms: float) -> void:
	var n: int = _layout.lots.size()
	while _block < n:
		_one_lot(_block)
		_block += 1
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			return


## Builds lot `i` of the layout (a house, a shop, a yard...) and stamps it into the map. The start lot: a family home of 22 x 16 (eight rooms) in a lot of 28 x 22 to 24 with two or three tiles to spare to the sides, no fence, no tree, no prop, no
## mark on its border and the tile inside it (a ring of free ground: the perimeter of the base goes there).
func _one_lot(i: int) -> void:
	var t_lot := Time.get_ticks_usec()
	var lot: Dictionary = _layout.lots[i]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 100003 + i * 7919 + 11
	var district := String(lot.district)
	var kind := String(lot.kind)
	var rect: Rect2i = lot.rect
	var start: bool = bool(lot.start)
	# ARRIVAL: a candidate's lot (`tier`) is a clear one like the start lot (a bare ring and yard, no fence, no flaw of the dice)
	var clear: bool = start or bool(lot.get("clear", false))
	var residential: bool = Districts.type_of(kind) == "residential"
	var spec := {"kind": kind, "district": district, "rect": rect, "front": String(lot.front), "plan": lot.plan, "seed": seed_value * 100003 + i, "start": start, "clear": clear,
		"mat": Districts.wall_code_for(district, rng, TownArt.WALL_MATS), "fenced": false, "yard": "lawn", "ruin": false, "barricade": false, "boarded": false}
	if district == Districts.SUBURB or district == Districts.EDGE:
		var yard_roll := rng.randf()
		spec.yard = "lawn" if yard_roll < (0.5 if district == Districts.SUBURB else 0.3) else ("garden" if yard_roll < 0.7 else ("bare" if yard_roll < 0.85 else "overgrown"))
	if clear:
		spec.yard = "lawn"
		if start:
			spec.mat = 1    # (the start house is brick, as the kit's sample is)
	else:
		var plan_d: Dictionary = lot.plan
		var margin: int = rect.size.x - (int(Vector2i(plan_d.box).x) if not plan_d.is_empty() else rect.size.x)
		if kind == "scrapyard" or kind == "containers":
			spec.fenced = true
		elif (kind == "warehouse" or kind == "garage") and rng.randf() < 0.5:
			spec.fenced = true
		elif (district == Districts.SUBURB or kind == "farmhouse") and kind != "terrace" and not _prev_fenced and margin >= 2 and rng.randf() < 0.3:
			spec.fenced = true
		if residential and not plan_d.is_empty() and Array(plan_d.parts).size() >= 2 and rng.randf() < 0.07:
			spec.ruin = true
		if residential and rng.randf() < 0.08:
			spec.barricade = true
		if residential and rng.randf() < 0.1:
			spec.boarded = true
		if residential and not bool(spec.ruin) and rng.randf() < 0.04:
			spec["burnt"] = true
		if district == Districts.SUBURB and kind != "terrace" and rng.randf() < 0.4:
			spec["shed"] = true
		elif district == Districts.EDGE and (kind == "farmhouse" or kind == "small" or kind == "medium") and rng.randf() < 0.6:
			spec["shed"] = true
	if bool(lot.get("in_field", false)):
		spec.fenced = false    # (CLEAR3: no fence line in a field of fire)
	_prev_fenced = bool(spec.fenced)
	var built: Dictionary = _builder.build(spec)
	if bool(lot.get("in_field", false)) and not clear and not (lot.plan as Dictionary).is_empty() and Fields.touches(built.buildings, _fields):
		# (CLEAR3: a building of this lot stands in a field of fire: the lot is built again as a vacant one, a meadow or a pocket of grass)
		lot.kind = "meadow" if rect.size.x >= 10 and rect.size.y >= 8 else "pocket"
		lot.plan = {}
		lot["vacated"] = true
		spec = {"kind": lot.kind, "district": district, "rect": rect, "front": String(lot.front), "plan": {}, "seed": seed_value * 100003 + i, "start": false, "clear": false,
			"mat": spec.mat, "fenced": false, "yard": "lawn", "ruin": false, "barricade": false, "boarded": false}
		_prev_fenced = false
		built = _builder.build(spec)
	if start:
		_clear_rect = rect
	if clear:
		_clear_rects.append(rect)
	_stamp_lot(built, lot, spec)
	_tick("blocks", t_lot)


## Copies a built lot into the town's arrays and, when it has a building, makes its House, Rooms, Doors and Containers.
func _stamp_lot(built: Dictionary, lot: Dictionary, spec: Dictionary) -> void:
	var cv = built.cv
	var rect: Rect2i = lot.rect
	var ox := rect.position.x
	var oy := rect.position.y
	var lw := rect.size.x
	var lh := rect.size.y
	var metal := int(_tids.WALL_METAL)
	var fence_style := _fence_style(int(lot.id), String(spec.kind), String(spec.district))
	for y in lh:
		for x in lw:
			var i := (oy + y) * _size + ox + x
			var j := y * lw + x
			_terrain[i] = cv.terrain[j]
			_solid[i] = cv.solid[j]
			if cv.terrain[j] == metal:
				_kit_line[i] = fence_style
	var dressing: Dictionary = built.dressing
	for g in dressing.ground:
		_kit_ground[(oy + int(g[1])) * _size + ox + int(g[0])] = int(g[2])
	for l in dressing.lines:
		_kit_line[(oy + int(l[1])) * _size + ox + int(l[0])] = int(l[2])
	for g in dressing.gates:
		# (a gate's leaves are drawn for the picket fences only: a chain link or a low wall has an opening)
		if bool(g.get("fenced", false)) and fence_style > 2:
			continue
		_gates.append({"x": ox + int(g.x), "y": oy + int(g.y), "w": int(g.w), "orient": String(g.orient)})
	var buildings: Array = built.buildings
	var first_id := _houses.size()
	for o in cv.objects:
		var shift_x := 0.0
		var shift_y := 0.0
		# a mark on the floor (a stain, papers: one tile) is kept inside its own lot, so that it never lies over a neighbour's ground (the start lot's ring is kept bare)
		if int(o.layer) == 1 and float(o.w) <= 1.0 and float(o.h) <= 1.0:
			shift_x = clampf(float(o.cx), 0.5, float(lw) - 0.5) - float(o.cx)
			shift_y = clampf(float(o.cy), 0.5, float(lh) - 0.5) - float(o.cy)
		o["cx"] = float(o.cx) + shift_x + float(ox)
		o["cy"] = float(o.cy) + shift_y + float(oy)
		for pc in o.pieces:
			pc["x"] = float(pc.x) + shift_x + float(ox)
			pc["y"] = float(pc.y) + shift_y + float(oy)
		# what stands inside a building's walls is that house's (the world draws it with the house, under its roof)
		if o.has("kit"):
			var at := Vector2i(floori(float(o.cx)), floori(float(o.cy)))
			for bi in buildings.size():
				for pr in buildings[bi].parts:
					if Rect2i(pr).has_point(at):
						o["in"] = first_id + bi
		_objects.append(o)
	for t in cv.trees:
		t["x"] = float(t.x) + float(ox)
		t["y"] = float(t.y) + float(oy)
		_trees.append(t)
	if buildings.is_empty():
		_lot_house.append(-1)
		if String(spec.kind) == "plaza" or String(spec.kind) == "park":
			_landmarks.append({"kind": "market" if String(spec.kind) == "plaza" else "park", "house": -1, "pos": Vector2(rect.get_center())})
		return
	var front := String(spec.front)
	_lot_house.append(first_id)
	if bool(lot.start):
		_start_house = first_id
	if String(lot.get("tier", "")) != "":
		_tiers.append({"house": first_id, "tier": String(lot.tier), "lot": int(lot.id)})
	# the rooms of every building of the lot (a room's "b" is the building it is in)
	var room_ids: Array = []
	var name_count: Array = []
	for bi in buildings.size():
		room_ids.append([])
		name_count.append({})
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var bi := int(a.get("b", 0))
		var house_id := first_id + bi
		var r: Rect2i = a.rect
		var rr := Rect2i(r.position.x + ox, r.position.y + oy, r.size.x, r.size.y)
		var nm := String(a.name)
		var n := int(name_count[bi].get(nm, 0)) + 1
		name_count[bi][nm] = n
		var room := {"id": "h%d:%s" % [house_id, nm] if n == 1 else "h%d:%s_%d" % [house_id, nm, n], "house": house_id, "name": nm, "rect": rr}
		room_ids[bi].append(_rooms.size())
		_rooms.append(room)
		_rooms_dict[String(room.id)] = [rr.position.x, rr.position.y, rr.end.x, rr.end.y]
	# the containers: only what is inside the walls can be searched (the search asks the house the avatar stands in)
	var reach: PackedByteArray = built.reach
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot.id) * 977 + 13 + seed_value * 31
	var affinity: Dictionary = _lay.affinity
	var cont_ids: Array = []
	for bi in buildings.size():
		cont_ids.append([])
	for c in cv.cands:
		# (the start house and the other candidates keep every container they have: they are where the run's first finds are)
		if rng.randf() > 0.85 and not bool(spec.get("clear", false)):
			continue
		var tile: Vector2i = SiteGen._stand_tile(cv, reach, c, rng)
		if tile.x < 0:
			continue
		var tt := Vector2i(tile.x + ox, tile.y + oy)
		var room_idx := -1
		var owner := -1
		for bi in buildings.size():
			for ri in room_ids[bi]:
				if Rect2i(_rooms[ri].rect).has_point(tt):
					room_idx = ri
					owner = bi
		if room_idx < 0:
			continue
		var weights: Dictionary = BuildingGen.loot_weights(String(_rooms[room_idx].name), String(buildings[owner].kind))
		var loot := {}
		for k in 2:
			var stock := _pick_stock(weights, rng)
			if SiteGen._fit(c, stock, affinity) > 0.0:
				loot[stock] = int(loot.get(stock, 0)) + rng.randi_range(1, 3)
		# (ARRIVAL: a candidate's container is never empty-handed: the other candidates, not the start house, which keeps its own dice, try again a few times)
		if loot.is_empty() and bool(spec.get("clear", false)) and not bool(spec.get("start", false)):
			for k in 6:
				var stock2 := _pick_stock(weights, rng)
				if loot.is_empty() and SiteGen._fit(c, stock2, affinity) > 0.0:
					loot[stock2] = rng.randi_range(1, 3)
		if loot.is_empty():
			continue
		var cid := "h%dc%d" % [first_id + owner, cont_ids[owner].size()]
		cont_ids[owner].append(cid)
		_containers.append({
			"id": cid, "house": first_id + owner, "room": room_idx,
			"pos": Vector2(float(tt.x) + 0.5, float(tt.y) + 0.5),
			"at": Vector2(float(c.obj.cx), float(c.obj.cy)),
			"kind": String(c.kind), "loot": loot, "search_s": 4.0,
		})
	# (CLEAR3: a candidate is never a house with nothing to search: the cottage's three small rooms drew no container, or no loot for it, in about one town of thirty; a box of food stands in the corner
	# of its roomiest room then)
	if bool(spec.get("clear", false)) and not bool(spec.get("start", false)) and not buildings.is_empty():
		var made := 0
		for lst in cont_ids:
			made += (lst as Array).size()
		if made == 0:
			_corner_box(first_id, room_ids[0], cont_ids[0], rng)
	var roof := Districts.roof_for(String(lot.district), rng)
	for bi in buildings.size():
		var bd: Dictionary = buildings[bi]
		var kind := String(bd.kind)
		var box: Rect2i = bd.box
		var front_h := box.position.y - rect.position.y if front == "N" else rect.end.y - box.end.y
		var front_yard := Rect2i(rect.position.x, rect.position.y, rect.size.x, front_h) if front == "N" else Rect2i(rect.position.x, box.end.y, rect.size.x, front_h)
		var back_yard := Rect2i(rect.position.x, box.end.y, rect.size.x, rect.end.y - box.end.y) if front == "N" else Rect2i(rect.position.x, rect.position.y, rect.size.x, box.position.y - rect.position.y)
		var door: Vector2i = bd.door
		var doors := _doors_of(bd.parts)
		var mat := int(spec.mat)
		_kit_house(first_id + bi, bd.parts, room_ids[bi], doors, mat, spec, bi == 0)
		var house := {
			"id": first_id + bi, "kind": kind, "var": String(bd.get("var", kind)), "facade": bd.get("facade", {}),
			"address": "%d %s" % [int(lot.number) + bi * 2, String(lot.street)],
			"block": Vector2i(int(lot.block), 0), "rect": box, "parts": bd.parts, "lot": rect, "front": front, "fenced": bool(spec.fenced),
			"door": door,
			"doors": doors,
			"rooms": room_ids[bi], "containers": cont_ids[bi], "dead": [],
			"district": String(lot.district), "type": Districts.type_of(kind), "yard": rect, "front_yard": front_yard, "back_yard": back_yard,
			"yard_type": String(spec.yard), "wall": String(TownArt.WALL_MATS[mat]), "roof": roof, "state": String(bd.state),
			"boarded": bool(spec.get("boarded", false)), "barricaded": bool(spec.get("barricade", false)) and bi == 0, "drive": bd.drive, "landmark": String(bd.landmark),
			"street": String(lot.street), "number": int(lot.number), "main": bi == 0,
		}
		if String(bd.landmark) != "":
			# the bell tower is the first part of the church: the landmark stands on it
			var tower: Rect2i = Array(bd.parts)[0]
			_landmarks.append({"kind": String(bd.landmark), "house": first_id + bi, "pos": Vector2(tower.get_center())})
		elif bi == 0 and kind in ["supermarket", "school", "fire_station", "police", "clinic"]:
			_landmarks.append({"kind": kind, "house": first_id + bi, "pos": Vector2(box.get_center())})
		_houses.append(house)


## CLEAR3: a box of food in a corner of the roomiest room of house `house_id` (`rooms`: its room indexes; `ids`: its container ids, which this adds to): a container with a place to stand, for a candidate
## home whose furniture made none. The corner is a free tile with a wall (or another prop) on two sides and a free tile of the room beside it; nothing happens when the room has none.
func _corner_box(house_id: int, rooms: Array, ids: Array, rng: RandomNumberGenerator) -> void:
	var props: Dictionary = _street_cv.props
	if rooms.is_empty() or not props.has("box") or not (props.box as Dictionary).has("kit"):
		return
	var room := -1
	var area := -1
	for ri in rooms:
		var rect: Rect2i = _rooms[int(ri)].rect
		if rect.get_area() > area:
			area = rect.get_area()
			room = int(ri)
	var rr: Rect2i = _rooms[room].rect
	var fp: Vector2i = _street_cv.tiles_of("box")
	var best := Vector2i(-1, -1)
	var stand := Vector2i(-1, -1)
	var best_score := -1.0
	for y in range(rr.position.y, rr.end.y - fp.y + 1):
		for x in range(rr.position.x, rr.end.x - fp.x + 1):
			var free := true
			for yy in fp.y:
				for xx in fp.x:
					if _solid[(y + yy) * _size + x + xx] != 0:
						free = false
			if not free:
				continue
			var shut := 0
			var spot := Vector2i(-1, -1)
			for d in [Vector2i(-1, 0), Vector2i(fp.x, 0), Vector2i(0, -1), Vector2i(0, fp.y)]:
				var p: Vector2i = Vector2i(x, y) + d
				if not rr.has_point(p) or _solid[p.y * _size + p.x] != 0:
					shut += 1
				elif spot.x < 0:
					spot = p
			if spot.x < 0 or shut < 2:
				continue
			var score := float(shut) + rng.randf() * 0.5
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
				stand = spot
	if best.x < 0:
		return
	var obj = _street_cv._decor("box", best.x, best.y, 0.0, 0.0)
	if obj == null:
		return
	_kit.kit_set(obj, props.box, rng)
	obj["solid"] = true
	obj["facing"] = "s"
	obj["in"] = house_id
	_objects.append(obj)
	for yy in fp.y:
		for xx in fp.x:
			_solid[(best.y + yy) * _size + best.x + xx] = 1
	var cid := "h%dc%d" % [house_id, ids.size()]
	ids.append(cid)
	_containers.append({"id": cid, "house": house_id, "room": room, "pos": Vector2(float(stand.x) + 0.5, float(stand.y) + 0.5), "at": Vector2(float(best.x) + float(fp.x) * 0.5, float(best.y) + float(fp.y) * 0.5),
		"kind": "box", "loot": {"food": rng.randi_range(1, 3)}, "search_s": 4.0})


## The line of a fenced lot (a code of TownArt.LINES): picket (white or brown), chain link or a low brick wall; chain link at the works.
func _fence_style(lot_id: int, kind: String, district: String) -> int:
	var h := (lot_id * 2246822519 + seed_value * 3266489917) & 0xffff
	var pick := h % 100
	if district == Districts.INDUSTRIAL or kind in ["scrapyard", "containers", "warehouse", "garage"]:
		# (WORLD3: chain link mostly, rusty wire now and then)
		return 3 if pick < 72 else 6
	if pick < 22:
		return 1
	if pick < 40:
		return 2
	if pick < 50:
		return 3
	if pick < 58:
		return 4
	# (WORLD3: a rusty wire fence, a tall board fence, a post and rail fence, an unkept hedge, a low stone wall)
	if pick < 68:
		return 6
	if pick < 80:
		return 7
	if pick < 89:
		return 8
	if pick < 95:
		return 9
	return 10


## The kit's data of one building: the floor of each room by its name, the material of the outside walls (`mat`, a code of TownArt.WALL_MATS) and of the walls inside, the windows (on the
## outside walls of every part, away from the corners, the doors and the walls inside; boarded in a house of the boarded sort, and in the start house on the west wall).
func _kit_house(house_id: int, parts: Array, room_ids: Array, doors: Array, mat: int, spec: Dictionary, main: bool) -> void:
	for ri in room_ids:
		var room: Dictionary = _rooms[ri]
		var fl := String(TownKit.FLOOR_OF.get(String(room.name), ""))
		var code := TownArt.GROUNDS.find(fl) + 1 if fl != "" else 0
		if code <= 0:
			continue
		var fr: Rect2i = room.rect
		for yy in range(fr.position.y, fr.end.y):
			for xx in range(fr.position.x, fr.end.x):
				_kit_ground[yy * _size + xx] = code
	var wall_t := int(_tids.WALL_BRICK)
	var plaster_t := int(_tids.WALL_PLASTER)
	var start_house := bool(spec.get("start", false)) and main
	# the walls inside: plaster mostly, a sage or sand wash in some houses (the start house keeps the plaster of the kit's sample)
	var inside := 7
	if not start_house:
		var ih := (house_id * 40503 + seed_value * 977) % 100
		inside = 7 if ih < 60 else (5 if ih < 80 else 4)
	for pr in parts:
		var rect: Rect2i = pr
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var t: int = _terrain[y * _size + x]
				if t == wall_t:
					_kit_wall[y * _size + x] = mat
				elif t == plaster_t:
					_kit_wall[y * _size + x] = inside
	var door_set := {}
	for dd in doors:
		for t in dd.tiles:
			door_set[t] = true
	var wrng := RandomNumberGenerator.new()
	wrng.seed = house_id * 7919 + seed_value * 131 + 5
	var boarded_house := bool(spec.get("boarded", false)) and main
	var boarded_bias := 0.05 if not start_house else 0.0
	var first_window := _windows.size()
	for pr in parts:
		var rect: Rect2i = pr
		for side in 4:
			var horiz := side < 2
			var span := rect.size.x if horiz else rect.size.y
			var pos := 2 + wrng.randi_range(0, 1)
			while pos < span - 2:
				var x := rect.position.x + pos if horiz else (rect.position.x if side == 2 else rect.end.x - 1)
				var y := (rect.position.y if side == 0 else rect.end.y - 1) if horiz else rect.position.y + pos
				var free := true
				for k in range(-1, 2):
					var q := Vector2i(x + k, y) if horiz else Vector2i(x, y + k)
					if door_set.has(q) or _terrain[q.y * _size + q.x] != wall_t:
						free = false
				# (not where a wall of the inside meets this one, and not in a wall that has another part of the building behind it)
				var inward := Vector2i(x, y + (1 if side == 0 else -1)) if horiz else Vector2i(x + (1 if side == 2 else -1), y)
				var outward := Vector2i(x, y + (-1 if side == 0 else 1)) if horiz else Vector2i(x + (-1 if side == 2 else 1), y)
				if _terrain[inward.y * _size + inward.x] == plaster_t or _in_parts(parts, outward):
					free = false
				if free:
					var r := wrng.randf()
					var state := "intact" if r < 0.74 - boarded_bias else ("broken" if r < 0.86 else "boarded")
					if boarded_house and wrng.randf() < 0.7:
						state = "boarded"
					_windows.append({"x": x, "y": y, "orient": "h" if horiz else "v", "state": state, "variant": wrng.randi_range(0, 1), "bar": false, "house": house_id})
				pos += 3 + wrng.randi_range(0, 1)
	# every room that has an outside wall has a window in it (the rows above go by the spacing along the wall and pass over a short room): the one tile of its wall nearest the middle
	# that is no door, no corner and no junction with a wall inside
	var lit := {}
	for k in range(first_window, _windows.size()):
		lit[Vector2i(int(_windows[k].x), int(_windows[k].y))] = true
	for ri in room_ids:
		var rr: Rect2i = _rooms[ri].rect
		for pr in parts:
			var part: Rect2i = pr
			for side in 4:
				var horiz := side < 2
				var wall_at := part.position.y if side == 0 else (part.end.y - 1 if side == 1 else (part.position.x if side == 2 else part.end.x - 1))
				var touches := rr.position.y == wall_at + 1 if side == 0 else (rr.end.y == wall_at if side == 1 else (rr.position.x == wall_at + 1 if side == 2 else rr.end.x == wall_at))
				if not touches:
					continue
				var a0 := rr.position.x if horiz else rr.position.y
				var a1 := rr.end.x if horiz else rr.end.y
				var has := false
				var best := -1
				var best_d := 1.0e9
				for t in range(a0, a1):
					var q := Vector2i(t, wall_at) if horiz else Vector2i(wall_at, t)
					if lit.has(q):
						has = true
						break
					var ok := true
					for kk in range(-1, 2):
						var q2 := Vector2i(t + kk, wall_at) if horiz else Vector2i(wall_at, t + kk)
						if door_set.has(q2) or _terrain[q2.y * _size + q2.x] != wall_t or lit.has(q2):
							ok = false
					var inward := Vector2i(t, wall_at + (1 if side == 0 else -1)) if horiz else Vector2i(wall_at + (1 if side == 2 else -1), t)
					if _terrain[inward.y * _size + inward.x] == plaster_t:
						ok = false
					var outward := Vector2i(t, wall_at + (-1 if side == 0 else 1)) if horiz else Vector2i(wall_at + (-1 if side == 2 else 1), t)
					if _in_parts(parts, outward):
						ok = false
					if ok:
						var d := absf(float(t) + 0.5 - float(a0 + a1) * 0.5)
						if d < best_d:
							best_d = d
							best = t
				if not has and best >= 0:
					var wx := best if horiz else wall_at
					var wy := wall_at if horiz else best
					lit[Vector2i(wx, wy)] = true
					_windows.append({"x": wx, "y": wy, "orient": "h" if horiz else "v", "state": "intact" if wrng.randf() < 0.8 else "broken", "variant": wrng.randi_range(0, 1), "bar": false, "house": house_id})
	# the start house: somebody has boarded up the windows on the west wall and put planks over one of them
	if start_house:
		var west: Array = []
		for k in range(first_window, _windows.size()):
			var w: Dictionary = _windows[k]
			for pr in parts:
				if int(w.x) == Rect2i(pr).position.x:
					west.append(w)
					break
		for k in west.size():
			west[k]["state"] = "boarded"
			west[k]["bar"] = k == 0


static func _pick_stock(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var at := rng.randf() * total
	for k in weights:
		at -= float(weights[k])
		if at < 0.0:
			return String(k)
	return "scrap"


## The doorways of a building: runs of door tiles in its parts (DOOR_WOOD); a doorway with open ground (outside every part) on one side is an exterior door of that wall.
func _doors_of(parts: Array) -> Array:
	var door_t := int(_tids.DOOR_WOOD)
	var seen := {}
	var out: Array = []
	for pr in parts:
		var rect: Rect2i = pr
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if _terrain[y * _size + x] != door_t or seen.has(Vector2i(x, y)):
					continue
				var p := Vector2i(x, y)
				# which way the wall runs: a doorway in a wall along x has wall (or doorway) to its west and east
				var horiz_wall := _wallish(x - 1, y) and _wallish(x + 1, y)
				var vert_wall := _wallish(x, y - 1) and _wallish(x, y + 1)
				if horiz_wall and vert_wall:
					horiz_wall = _terrain[y * _size + x + 1] == door_t or _terrain[y * _size + x - 1] == door_t
				elif not horiz_wall and not vert_wall:
					horiz_wall = true
				var tiles: Array = [p]
				seen[p] = true
				var step := Vector2i(1, 0) if horiz_wall else Vector2i(0, 1)
				var q := p + step
				while q.x < _size and q.y < _size and _terrain[q.y * _size + q.x] == door_t and not seen.has(q):
					tiles.append(q)
					seen[q] = true
					q += step
				var first: Vector2i = tiles[0]
				var side_a := first + (Vector2i(0, -1) if horiz_wall else Vector2i(-1, 0))
				var side_b := first + (Vector2i(0, 1) if horiz_wall else Vector2i(1, 0))
				var a_out := not _in_parts(parts, side_a)
				var b_out := not _in_parts(parts, side_b)
				var side := ""
				var exterior := true
				var out_tile := side_a
				var in_tile := side_b
				if a_out and not b_out:
					side = "N" if horiz_wall else "W"
				elif b_out and not a_out:
					side = "S" if horiz_wall else "E"
					out_tile = side_b
					in_tile = side_a
				else:
					exterior = false
					side = "H" if horiz_wall else "V"
				out.append({"tiles": tiles, "exterior": exterior, "side": side, "out": out_tile, "in": in_tile})
	return out


func _wallish(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _size or y >= _size:
		return false
	return _solid[y * _size + x] != 0 or _terrain[y * _size + x] == int(_tids.DOOR_WOOD)


static func _in_parts(parts: Array, p: Vector2i) -> bool:
	for pr in parts:
		if Rect2i(pr).has_point(p):
			return true
	return false


# ----------------------------------------------------------- the edge, the streets' things --

func _edge_and_furniture(piece: int) -> void:
	var t0 := Time.get_ticks_usec()
	Streetscape.step(self, piece)
	_tick("street_furniture", t0)


func _add_tree(tx: int, ty: int, shut: bool) -> void:
	var n := _rng.randi_range(0, 12)
	_trees.append({"x": float(tx) + 0.5, "y": float(ty) + 0.55, "variant": n % 3, "file": "res://assets/trees/tree_%d.png" % n})
	if shut:
		_solid[ty * _size + tx] = 1


# ------------------------------------------------------------------ the map, the indexes --

## The piece `piece` (0 to FINISH_STEPS - 1) of the map's finish: the objects in drawing order, the arrays of the data, the tile indexes.
func _finish_map(piece: int) -> void:
	var t0 := Time.get_ticks_usec()
	match piece:
		0:
			_scrubbed = Fields.scrub(self)
			_scrubbed["dressed"] = Fields.dress(self)
			_finish_objects()
		1:
			_finish_data()
		_:
			_finish_tiles()
	_tick("finish", t0)


## The objects in drawing order: by layer and the bottom of their footprint, then by their id in the lot they were made in. (The keys are made once and an index list is sorted by them, the same
## comparison as the objects' own, so that the order is what sorting the dictionaries gave; reading a dictionary four times a comparison was most of this piece.)
func _finish_objects() -> void:
	var n := _objects.size()
	var keys := PackedFloat64Array()
	var ids := PackedInt32Array()
	keys.resize(n)
	ids.resize(n)
	for i in n:
		var o: Dictionary = _objects[i]
		keys[i] = float(o.layer) * 1000.0 + float(o.cy) + float(o.h) / 2.0
		ids[i] = int(o.id)
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int):
		var ka := keys[a]
		var kb := keys[b]
		if ka != kb:
			return ka < kb
		return ids[a] < ids[b])
	var sorted: Array = []
	sorted.resize(n)
	for i in n:
		var o: Dictionary = _objects[int(order[i])]
		o["id"] = i
		o["order"] = i
		sorted[i] = o
	_objects = sorted


func _finish_data() -> void:
	var W := _size
	var H := _size
	var shut: Array = Array(_solid)
	var zeros: Array = []
	zeros.resize(W * H)
	zeros.fill(0)
	var d := _base.duplicate(false)
	d["W"] = W
	d["H"] = H
	d["terrainTypes"] = _terrain_types
	d["terrain"] = Array(_terrain)
	d["solidZ"] = shut
	d["solidP"] = shut.duplicate()
	# (SHOT OVER FURNITURE: the tiles under the LOW props, 1 where a bed, a sofa, a table or a counter stands: a bullet, a blow and the dead's eye go over them though nobody walks through;
	# assets/data/prop_heights.json. Rebuilt from the seed with the town, saved nowhere; the school's and the raid sites' data have no such key)
	d["shot_low"] = PropHeights.shot_low_grid(_objects, W, H)
	d["wall"] = zeros
	d["objects"] = _objects
	d["marks"] = _marks
	d["walls"] = []
	d["segments"] = []
	d["trees"] = _trees
	d["lights"] = []
	d["rooms"] = _rooms_dict
	d["spawns"] = [_spawn_point()]
	d["yard"] = [1, 1, W - 1, H - 1]
	d["people"] = []
	d["bonds"] = []
	var house_rects: Array = []
	for h in _houses:
		var hr: Rect2i = h.rect
		house_rects.append([hr.position.x, hr.position.y, hr.size.x, hr.size.y])
	d["kit"] = {"ground": _kit_ground, "wall": _kit_wall, "line": _kit_line, "windows": _windows, "gates": _gates, "houses": house_rects}
	d["workshop"] = {"x": 0.0, "y": 0.0, "what": "At home"}
	_result = {"data": d}


## Which house and which room holds each tile.
func _finish_tiles() -> void:
	var W := _size
	var H := _size
	_tile_house.resize(W * H)
	_tile_house.fill(-1)
	_tile_room.resize(W * H)
	_tile_room.fill(-1)
	for h in _houses:
		for r in h.parts:
			var pr: Rect2i = r
			for y in range(pr.position.y, pr.end.y):
				for x in range(pr.position.x, pr.end.x):
					_tile_house[y * W + x] = int(h.id)
	for ri in _rooms.size():
		var rr: Rect2i = _rooms[ri].rect
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				_tile_room[y * W + x] = ri


## Where the waves come in until a base says otherwise: on the road that runs out of the town at the north, a little inside the border.
func _spawn_point() -> Array:
	var best: Array = []
	for rd in _layout.roads:
		var r: Rect2i = rd.rect
		if bool(rd.through) and String(rd.dir) == "v" and r.position.y <= EDGE:
			return [float(r.position.x) + float(r.size.x) * 0.5, float(EDGE) + 2.5]
		if best.is_empty() and String(rd.kind) != "alley":
			best = [float(r.position.x) + float(r.size.x) * 0.5, float(r.position.y) + float(r.size.y) * 0.5]
	return best if not best.is_empty() else [float(_size) * 0.5, float(EDGE) + 2.5]


# ------------------------------------------------------- the start, the rescues, the dead --

## What the pieces of `_people` hand on to each other: "legacy" (a town without an arrival: the start house is the only candidate and its start is inside it), "start_house", "start_room",
## "start_pos", "entry", "cands" (the candidates, best first), "rescue_for" (house id as a String -> the rescue list), "rescue_i", "check_i", "walk" (the walk's state), "dead".
var _pp := {}


## The piece `piece` (0 to PEOPLE_STEPS - 1) of the people: the arrival (the entry, the candidates), the rescue lists, the dead, the result's lists of the map and the streets, the candidates
## checked against the base's rules (one at a time), the walk from the entry to them (a piece at a time), the lots, districts and the stats. True when the piece is done (else it is asked again).
func _people(piece: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var done := true
	match piece:
		0:
			_people_arrival()
			_tick("people_and_dead", t0)
		1:
			done = _people_rescue()
			_tick("people_and_dead", t0)
		2:
			_people_dead()
			_tick("people_and_dead", t0)
		3:
			_people_result()
			_tick("result", t0)
		4:
			done = _people_check()
			_tick("arrival_check", t0)
		5:
			done = _people_walk()
			_tick("arrival_check", t0)
		_:
			_people_lists()
			_tick("result", t0)
	return done


# --------------------------------------------------------------------- the arrival --

## The name each kind of home is given in a candidate's label.
const KIND_NAMES := {"start": "Family home", "family": "Family home", "medium": "House", "small": "Small house", "bungalow": "Bungalow", "cottage": "Cottage", "terrace": "Terrace house",
	"terrace_ext": "Terrace house", "lhouse": "House", "thouse": "House", "uhouse": "Large house", "twowing": "Large house"}
const TIER_ORDER := ["best", "ok", "poor"]


## The start house (the family home of the clear lot the layout made), the entry and the candidates (the houses of the lots that have a tier: the start lot, the house of the middle sort and the
## cottage beside the avenue; a town without an arrival has the start house alone), and where the avatar starts. Nothing is checked here: `_people_check` does that.
func _people_arrival() -> void:
	var d: Dictionary = _result.data
	# the start house: the family home of the clear lot the block loop made
	var start_house := _start_house
	if start_house < 0:
		# (TOWNGEN: the layout always makes a start lot; if a seed ever fails to, the residential house nearest the middle of the town stands in)
		var best_d := INF
		start_house = 0
		for h in _houses:
			if String(h.type) == "residential" and h.rooms.size() >= 3:
				var dd := Vector2(Rect2i(h.rect).get_center()).distance_to(Vector2(float(_size) * 0.5, float(_size) * 0.5))
				if dd < best_d:
					best_d = dd
					start_house = int(h.id)
		push_warning("town: no start lot, house %d stands in" % start_house)
	var legacy: bool = _layout.arrival.is_empty()
	# the entry: the end of the main avenue the avatar comes in at (a town without an arrival: the west end), 4 or 5 tiles inside the map's edge, facing into town
	var entry := {}
	var arr: Dictionary = _layout.arrival
	var avenue: Dictionary = {} if int(_layout.avenue) < 0 else _layout.roads[int(_layout.avenue)]
	if not arr.is_empty():
		entry = {"pos": arr.pos, "face": String(arr.face), "road": arr.road}
	elif not avenue.is_empty():
		var ar: Rect2i = avenue.rect
		entry = {"pos": Vector2(float(EDGE) + 2.5, float(ar.position.y) + 3.5), "face": "E", "road": Rect2i(EDGE, ar.position.y, 14, ar.size.y)}
	else:
		entry = {"pos": Vector2(Vector2i(_houses[start_house].door)) + Vector2(0.5, 0.5), "face": "S", "road": Rect2i()}
	var road_name := String(avenue.get("name", "Main Street")) if not avenue.is_empty() else "the road"
	entry["label"] = "%s, %s end" % [road_name, "east" if String(entry.face) == "W" else "west"]
	entry["sign"] = _entry_sign
	entry["arrows"] = _entry_arrows
	# the candidates, best first
	var cands: Array = []
	if legacy:
		cands.append({"house": start_house, "tier": "best"})
	else:
		for t in _tiers:
			cands.append({"house": int(t.house), "tier": String(t.tier)})
		cands.sort_custom(func(a, b): return TIER_ORDER.find(String(a.tier)) < TIER_ORDER.find(String(b.tier)))
	if cands.is_empty():
		# (never without one: the layout always makes the arrival's lots, but should a plan not fit, the start house stands alone)
		cands.append({"house": start_house, "tier": "best"})
	for c in cands:
		var h: Dictionary = _houses[int(c.house)]
		var rooms: int = h.rooms.size()
		var area := 0
		for pr in h.parts:
			area += Rect2i(pr).get_area()
		# (the yard: what is left of the lot beside and round the walls)
		var free := Rect2i(h.lot).get_area() - area
		c["kind"] = String(h.kind)
		c["rooms"] = rooms
		c["yard_tiles"] = free
		c["yard"] = "big" if free >= YARD_BIG else ("small" if free >= YARD_SMALL else "none")
		c["label"] = "%s. %d rooms, %s." % [String(KIND_NAMES.get(String(h.kind), String(h.kind).capitalize())), rooms, "no yard" if String(c.yard) == "none" else "%s yard" % String(c.yard)]
		c["door"] = Vector2(Vector2i(h.door)) + Vector2(0.5, 0.5)
		c["dist"] = Vector2(c.door).distance_to(Vector2(entry.pos))
		# (what `_people_check` and `_people_walk` find out; a town without an arrival has no checks to make: its candidate stands as it is)
		c["problems"] = []
		c["ring"] = {"free": 0, "blocked": 0}
		c["walk"] = int(ceil(float(c.dist)))
	# where the avatar starts: the entry; a town without an arrival keeps the start inside the house (the title's town, the tests' small ones)
	var start_room := -1
	var start_pos := Vector2(entry.pos)
	if legacy:
		start_room = _start_room(start_house)
		start_pos = _free_spot(start_room)
	d["workshop"] = {"x": start_pos.x, "y": start_pos.y - 1.0, "what": "At home"}
	_pp = {"legacy": legacy, "start_house": start_house, "start_room": start_room, "start_pos": start_pos, "entry": entry, "cands": cands, "rescue_for": {}, "rescue_i": 0, "check_i": 0}
	_pp["calm"] = _calm_points(entry, cands, legacy)


## How much of a lot is free (tiles, the lot less the walls' footprint) that a candidate's yard is big, and small (less is none).
const YARD_BIG := 215
const YARD_SMALL := 110
## How near the entry and the candidates the streets and the yards are left without a dead one (tiles), and the dead of the houses near them are thinned.
const CALM_R := 20.0


## The points the dead keep away from: the entry and the middle of every candidate (a town without an arrival: the start house's middle).
func _calm_points(entry: Dictionary, cands: Array, legacy: bool) -> Array:
	var out: Array = []
	if not legacy:
		out.append(Vector2(entry.pos))
	for c in cands:
		out.append(Vector2(Rect2i(_houses[int(c.house)].rect).get_center()))
	return out


## The middle of every house whose spawn roads are kept clear of parked cars (`Streetscape._cars`): the candidates (the start house in a town without an arrival).
func _base_centers() -> Array:
	var out: Array = []
	if _tiers.is_empty():
		if _start_house >= 0:
			out.append(Vector2(Rect2i(_houses[_start_house].rect).get_center()))
		return out
	for t in _tiers:
		out.append(Vector2(Rect2i(_houses[int(t.house)].rect).get_center()))
	return out


## Whether a tile is on or within `grow` tiles of a clear lot (a candidate's, the start lot's).
func _in_clear(t: Vector2i, grow: int) -> bool:
	for r in _clear_rects:
		if Rect2i(r).grow(grow).has_point(t):
			return true
	return false


## The rescue lists, one candidate a call (each is the rules of the old single list, from that candidate's house): true when every candidate has one.
func _people_rescue() -> bool:
	var cands: Array = _pp.cands
	var exclude := {}
	for c in cands:
		exclude[int(c.house)] = true
	var i := int(_pp.rescue_i)
	if i < cands.size():
		var hid := int(cands[i].house)
		_pp.rescue_for[str(hid)] = _rescue_set(hid, exclude)
		_pp.rescue_i = i + 1
	return int(_pp.rescue_i) >= cands.size()


## The rescue list of a candidate: RESCUE_COUNT houses (two in a town of less than 6 blocks) near to far from it, none of them a candidate.
func _rescue_set(start_house: int, exclude: Dictionary) -> Array:
	var rng := _rng
	var start_c := Vector2(Rect2i(_houses[start_house].rect).get_center())
	# the rescue candidates, one ring after another round the start (the rings are 22 to 48 tiles, 48 to 80, 80 and more in the full town, a third of that
	# in a small one), spread apart: RESCUE_COUNT of the full town, `opts.rescue` of any
	var rescue: Array = []
	var scale := float(_size) / float(DEFAULT_SIZE)
	var want := int(opts.get("rescue", RESCUE_COUNT if _blocks >= 6 else 2))
	var apart_min := 18.0 if _blocks >= 6 else 8.0
	# (WP8: the first ring is 14 to 28 tiles out, not 22 to 48: the first rescue is the demo's first goal, to be reached with a pump shotgun and 40 rounds)
	# (BIGGER HOUSES: the first ring is 14 to 34 tiles out, not 14 to 28: there are fewer houses to find a survivor in)
	var rings := [[14.0 * scale, 34.0 * scale], [34.0 * scale, 62.0 * scale], [62.0 * scale, 400.0]]
	if not _fields.is_empty():
		# (CLEAR3: a candidate has open ground 10 tiles wide round its fence, and every lot that touched it is vacant: the first house is 30 or more tiles from its middle, and 4 or 5 of them
		# stand within 56; the rings begin where the houses do, 16 tiles later than they did)
		rings = [[30.0 * scale, 56.0 * scale], [56.0 * scale, 84.0 * scale], [84.0 * scale, 400.0]]
	var per_ring := int(ceil(float(want) / 3.0))
	for ri in rings.size():
		# (BIGGER HOUSES: the survivors are found in family homes and the bigger detached ones, `_rescue_rank` 0; the next best where a ring has not enough of them, so that every ring still
		# has its share of them, near to far; a block of flats or a shop only in `_top_up_rescue`, when nothing else is left)
		var picked := 0
		for rank in 4:
			var pool: Array = []
			for h in _houses:
				if int(h.id) == start_house or exclude.has(int(h.id)) or _rescue_rank(h) != rank:
					continue
				var dist := Vector2(Rect2i(h.rect).get_center()).distance_to(start_c)
				if dist >= rings[ri][0] and dist < rings[ri][1]:
					pool.append(int(h.id))
			var guard := 0
			while picked < per_ring and rescue.size() < want and not pool.is_empty() and guard < 200:
				guard += 1
				var hid: int = pool[rng.randi() % pool.size()]
				var c := Vector2(Rect2i(_houses[hid].rect).get_center())
				var apart := true
				for r in rescue:
					if Vector2(Rect2i(_houses[int(r.house)].rect).get_center()).distance_to(c) < apart_min:
						apart = false
				if not apart:
					pool.erase(hid)
					continue
				var room := _rescue_room(hid)
				rescue.append({"house": hid, "pos": _hide_spot(room, hid), "room": room, "ring": ri + 1, "dist": c.distance_to(start_c)})
				pool.erase(hid)
				picked += 1
	_top_up_rescue(rescue, want, start_house, exclude, start_c, apart_min)
	rescue.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return rescue


func _people_dead() -> void:
	# the houses with a survivor in any candidate's rescue list, once each (a house keeps the room it was given): the dead that guard them
	var guards: Array = []
	var seen := {}
	for c in _pp.cands:
		for r in _pp.rescue_for[str(int(c.house))]:
			if not seen.has(int(r.house)):
				seen[int(r.house)] = true
				guards.append(r)
	var dead := _dead(_pp.cands, guards, int(_pp.start_room), _pp.calm, bool(_pp.legacy))
	for i in dead.size():
		var hid := int(dead[i].house)
		if hid >= 0:
			_houses[hid].dead.append(i)
	_pp["dead"] = dead


## The result's own entries: the lists of the town, the start, the rescue list and the streets.
func _people_result() -> void:
	var W := _size
	var H := _size
	_ms["total"] = float(Time.get_ticks_usec() - _started) / 1000.0
	_result["seed"] = seed_value
	_result["version"] = VERSION
	_result["size"] = Vector2i(W, H)
	_result["houses"] = _houses
	_result["rooms"] = _rooms
	_result["containers"] = _containers
	_result["dead"] = _pp.dead
	# (ARRIVAL: `start` is kept for what reads it: the best candidate, and the entry where the avatar stands, outside every house, `room` -1; `rescue` is the best candidate's list)
	_result["start"] = {"house": int(_pp.start_house), "pos": _pp.start_pos, "room": int(_pp.start_room), "ring": _ring_report(int(_pp.start_house))}
	_result["entry"] = _pp.entry
	_result["candidates"] = _pp.cands
	_result["rescue_for"] = _pp.rescue_for
	_result["rescue"] = _pp.rescue_for[str(int(_pp.start_house))]
	_result["tile_house"] = _tile_house
	_result["tile_room"] = _tile_room
	# (CLEAR3: the fields of fire of the candidates, each the candidate's lot grown by 10 tiles: no other building and nothing tall stands in them)
	_result["fields"] = _fields
	var names_x: Array = []
	var names_y: Array = []
	var roads_sorted: Array = _layout.roads.duplicate()
	roads_sorted.sort_custom(func(a, b): return (Rect2i(a.rect).position.x + Rect2i(a.rect).position.y) < (Rect2i(b.rect).position.x + Rect2i(b.rect).position.y))
	for rd in roads_sorted:
		if String(rd.kind) == "alley":
			continue
		if String(rd.dir) == "v":
			names_x.append(String(rd.name))
		else:
			names_y.append(String(rd.name))
	var roads_out: Array = []
	for rd in _layout.roads:
		roads_out.append({"id": int(rd.id), "name": String(rd.name), "dir": String(rd.dir), "rect": rd.rect, "kind": String(rd.kind), "through": bool(rd.through)})
	_result["streets"] = {"pitch": PITCH, "block": BLOCK, "road": ROAD, "names_x": names_x, "names_y": names_y, "roads": roads_out, "avenue": int(_layout.avenue)}


## The candidates against the base's rules, one a call: the base's layout is made on the house and checked (`BaseLayout.validate`, the problems kept on the candidate: `problems`, empty is good).
## A town without an arrival has nothing to check (its one candidate is the start house, as ever). True when every candidate has been.
func _people_check() -> bool:
	if bool(_pp.legacy):
		return true
	var cands: Array = _pp.cands
	var i := int(_pp.check_i)
	if i < cands.size():
		var c: Dictionary = cands[i]
		if not _pp.has("kits"):
			_pp["kits"] = BaseLayout.load_kits()
		var lay: Dictionary = BaseLayout.make(_result, int(c.house), {"kits": _pp.kits})
		c["problems"] = BaseLayout.validate(lay, _result)
		c["ring"] = {"free": int(lay.ring.free), "blocked": int(lay.ring.blocked)}
		_pp.check_i = i + 1
	return int(_pp.check_i) >= cands.size()


## The walk from the entry to the front door of every candidate: a breadth first flood of the walkable ground from the entry tile, a piece of it a call (`WALK_POPS` tiles); `walk` on
## each candidate is the length of the way in tiles (4 ways, so a little more than the avatar's), -1 when there is none. True when every door has been reached or the flood is done.
const WALK_POPS := 3000
func _people_walk() -> bool:
	if bool(_pp.legacy):
		return true
	var W := _size
	if not _pp.has("walk"):
		var dist0 := PackedInt32Array()
		dist0.resize(W * W)
		dist0.fill(-1)
		var q0 := PackedInt32Array()
		q0.resize(W * W)
		var e: Vector2 = _pp.entry.pos
		var first := floori(e.y) * W + floori(e.x)
		dist0[first] = 0
		q0[0] = first
		_pp["walk"] = {"dist": dist0, "q": q0, "head": 0, "tail": 1}
	var w: Dictionary = _pp.walk
	var dist: PackedInt32Array = w.dist
	var q: PackedInt32Array = w.q
	var head := int(w.head)
	var tail := int(w.tail)
	var pops := 0
	while head < tail and pops < WALK_POPS:
		var i := q[head]
		head += 1
		pops += 1
		var x := i % W
		@warning_ignore("integer_division")
		var y := i / W
		var nd := dist[i] + 1
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= W:
				continue
			var j := ny * W + nx
			if dist[j] != -1 or _solid[j] != 0:
				continue
			dist[j] = nd
			q[tail] = j
			tail += 1
	w["head"] = head
	w["tail"] = tail
	var all_found := true
	for c in _pp.cands:
		var dt := Vector2i(Vector2(c.door))
		if dist[dt.y * W + dt.x] < 0:
			all_found = false
	if all_found or head >= tail:
		for c in _pp.cands:
			var dt := Vector2i(Vector2(c.door))
			c["walk"] = dist[dt.y * W + dt.x]
		_pp.erase("walk")
		return true
	return false


## The result's districts, lots, landmarks and stats; the candidates that stand (a town with an arrival keeps those with no problem of the base's rules and a way from the entry to their door,
## best first; `start` and `rescue` follow the best of them).
func _people_lists() -> void:
	var dead: Array = _pp.dead
	var dropped: Array = []
	if not bool(_pp.legacy):
		var keep: Array = []
		for c in _pp.cands:
			if Array(c.problems).is_empty() and int(c.walk) >= 0:
				keep.append(c)
			else:
				dropped.append({"house": int(c.house), "tier": String(c.tier), "problems": c.problems, "walk": int(c.walk)})
		if keep.is_empty():
			# (never an empty list: the first candidate stands with the problems it has, told in `stats.arrival`)
			keep.append(_pp.cands[0])
			dropped.erase(dropped[0])
		for c in dropped:
			_result.rescue_for.erase(str(int(c.house)))
		keep.sort_custom(func(a, b): return TIER_ORDER.find(String(a.tier)) < TIER_ORDER.find(String(b.tier)) or (a.tier == b.tier and float(a.dist) < float(b.dist)))
		_result["candidates"] = keep
		var best_house := int(keep[0].house)
		if best_house != int(_result.start.house):
			_result.start["house"] = best_house
			_result.start["ring"] = _ring_report(best_house)
		_result["rescue"] = _result.rescue_for[str(best_house)]
	var by_kind := {}
	for h in _houses:
		by_kind[h.kind] = int(by_kind.get(h.kind, 0)) + 1
	# TOWNGEN: the districts (a tile map and the blocks), the lots, the landmarks
	var area := {}
	var district_names: Array = Districts.ALL
	# (a count by index first and the names after, in the order the districts first appear on the map: a tile map is 36864 bytes, and a dictionary update a tile was most of this piece)
	var counts := PackedInt32Array()
	counts.resize(district_names.size() + 1)
	var order: Array = []
	for v in _layout.district_map:
		if v > 0:
			if counts[v] == 0:
				order.append(v)
			counts[v] += 1
	for di in order:
		area[String(district_names[di - 1])] = counts[di]
	var blocks_out: Array = []
	for b in _layout.blocks:
		blocks_out.append({"id": int(b.id), "rect": b.rect, "district": String(b.district), "role": String(b.role)})
	_result["districts"] = {"names": district_names, "map": _layout.district_map, "blocks": blocks_out, "area": area, "ring": int(_layout.ring)}
	var lots_out: Array = []
	for lot in _layout.lots:
		lots_out.append({"id": int(lot.id), "rect": lot.rect, "front": String(lot.front), "district": String(lot.district), "kind": String(lot.kind), "block": int(lot.block),
			"street": String(lot.street), "house": int(_lot_house[int(lot.id)]) if int(lot.id) < _lot_house.size() else -1, "start": bool(lot.start), "tier": String(lot.get("tier", "")),
			"vacated": bool(lot.get("vacated", false))})
	_result["lots"] = lots_out
	_result["landmarks"] = _landmarks + _layout.landmarks
	var by_district := {}
	var by_type := {}
	var part_count := 0
	var room_min := 1000
	var room_max := 0
	for h in _houses:
		by_district[h.district] = int(by_district.get(h.district, 0)) + 1
		by_type[h.type] = int(by_type.get(h.type, 0)) + 1
		part_count += h.parts.size()
		room_min = mini(room_min, h.rooms.size())
		room_max = maxi(room_max, h.rooms.size())
	_result["stats"] = {"houses": _houses.size(), "by_kind": by_kind, "by_district": by_district, "by_type": by_type, "parts": part_count, "rooms_per_house": [room_min, room_max],
		"rooms": _rooms.size(), "containers": _containers.size(), "dead": dead.size(), "objects": _objects.size(), "trees": _trees.size(), "street_objects": _street_objs, "ms": _ms,
		"arrival": {"on": not bool(_pp.legacy), "dropped": dropped, "best_side": String(_layout.arrival.get("best", ""))},
		"fields": {"count": _fields.size(), "scrubbed": _scrubbed, "vacated": _vacated_count()}}


## How many lots the fields of fire made vacant (CLEAR3).
func _vacated_count() -> int:
	var n := 0
	for lot in _layout.lots:
		if bool(lot.get("vacated", false)):
			n += 1
	return n


## The clear ring of the start lot, for the tests and the layout: the lot's rectangle, and how many tiles of its border and the row inside it are free (open ground,
## no picture of a prop, a tree or a mark on them). `free == total` is the promise.
func _ring_report(house_id: int) -> Dictionary:
	var lot: Rect2i = _houses[house_id].lot
	var taken := {}
	for o in _objects:
		var x0 := floori(float(o.cx) - float(o.w) / 2.0 + 0.01)
		var x1 := ceili(float(o.cx) + float(o.w) / 2.0 - 0.01)
		var y0 := floori(float(o.cy) - float(o.h) / 2.0 + 0.01)
		var y1 := ceili(float(o.cy) + float(o.h) / 2.0 - 0.01)
		# (only what touches the lot matters: the tiles are asked about inside it below)
		if x1 <= lot.position.x or x0 >= lot.end.x or y1 <= lot.position.y or y0 >= lot.end.y:
			continue
		for y in range(y0, y1):
			for x in range(x0, x1):
				taken[Vector2i(x, y)] = true
	for t in _trees:
		taken[Vector2i(floori(float(t.x)), floori(float(t.y)))] = true
	var total := 0
	var free := 0
	for y in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			var edge := mini(mini(x - lot.position.x, lot.end.x - 1 - x), mini(y - lot.position.y, lot.end.y - 1 - y))
			if edge > 1:
				continue
			total += 1
			if _solid[y * _size + x] == 0 and not taken.has(Vector2i(x, y)):
				free += 1
	return {"rect": lot, "total": total, "free": free}


## How good a house is to find a survivor in (BIGGER HOUSES): 0 a family home or one of the bigger detached houses with five rooms or more, 1 one of those kinds with three, 2 any other
## home but a cottage with three rooms or more (a small house, a terrace), 3 a cottage, 4 a block of flats, a shop, a works or a public building with two rooms or more, -1 never (a shed,
## the buildings of a lot that are not its main one).
func _rescue_rank(h: Dictionary) -> int:
	var kind := String(h.kind)
	var n: int = h.rooms.size()
	if not bool(h.main) or kind == "shed" or n < 2:
		return -1
	if Plans.RESCUE_KINDS.has(kind) and n >= 5:
		return 0
	if Plans.RESCUE_KINDS.has(kind) and n >= 3:
		return 1
	if String(h.type) == "residential" and kind != "cottage" and kind != "apartments" and n >= 3:
		return 2
	return 3 if (String(h.type) == "residential" and kind != "apartments") else 4


## The room a survivor hides in: a bedroom (one of them), else the study, the dining room, the utility room, the living room, else the roomiest that is no hall.
func _rescue_room(house_id: int) -> int:
	# (ARRIVAL: a house in the lists of two candidates keeps the room it was given the first time)
	if _rescue_rooms.has(house_id):
		return int(_rescue_rooms[house_id])
	var rooms: Array = _houses[house_id].rooms
	var picked := -1
	for nm in ["bedroom", "study", "dining room", "utility", "nursery", "living room", "kitchen", "garage"]:
		var cands: Array = []
		for ri in rooms:
			if String(_rooms[ri].name) == nm:
				cands.append(int(ri))
		if not cands.is_empty():
			picked = int(cands[_rng.randi() % cands.size()])
			break
	if picked < 0:
		picked = _roomiest(house_id)
	_rescue_rooms[house_id] = picked
	return picked


## The room the avatar wakes in: the living room of the start house (the roomiest room when it has none).
func _start_room(house_id: int) -> int:
	for ri in _houses[house_id].rooms:
		if String(_rooms[ri].name) == "living room":
			return int(ri)
	return _roomiest(house_id)


## The free floor tiles of a room (for the survivor's room's dead).
func _rescue_room_tiles(room: int) -> Array:
	var rr: Rect2i = _rooms[room].rect
	var out: Array = []
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if _solid[y * _size + x] == 0:
				out.append(Vector2i(x, y))
	return out


## The index of the roomiest room of a house.
func _roomiest(house_id: int) -> int:
	var best := -1
	var best_area := -1
	for ri in _houses[house_id].rooms:
		var rr: Rect2i = _rooms[ri].rect
		if rr.size.x * rr.size.y > best_area:
			best_area = rr.size.x * rr.size.y
			best = int(ri)
	return best


## A free tile near the middle of a room, as a point in tiles.
func _free_spot(room: int) -> Vector2:
	var rr: Rect2i = _rooms[room].rect
	var mid := Vector2(rr.get_center())
	var best := Vector2(mid.x + 0.5, mid.y + 0.5)
	var best_d := INF
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if _solid[y * _size + x] != 0:
				continue
			var dd := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(mid)
			if dd < best_d:
				best_d = dd
				best = Vector2(float(x) + 0.5, float(y) + 0.5)
	return best


## WP8: a ring that holds too few houses far enough apart leaves the rescue list short: the nearest houses not picked yet (two rooms or more, half the usual space from the others) make
## it up, so that there are always `want` of them.
func _top_up_rescue(rescue: Array, want: int, start_house: int, exclude: Dictionary, start_c: Vector2, apart_min: float) -> void:
	var spare: Array = []
	for h in _houses:
		if int(h.id) == start_house or exclude.has(int(h.id)) or _rescue_rank(h) < 0:
			continue
		var taken := false
		for r in rescue:
			taken = taken or int(r.house) == int(h.id)
		if not taken:
			# (the better houses first, the nearest first among them)
			spare.append([float(_rescue_rank(h)) * 1000.0 + Vector2(Rect2i(h.rect).get_center()).distance_to(start_c), int(h.id)])
	spare.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for e in spare:
		if rescue.size() >= want:
			return
		var hid := int(e[1])
		var c := Vector2(Rect2i(_houses[hid].rect).get_center())
		var apart := true
		for r in rescue:
			if Vector2(Rect2i(_houses[int(r.house)].rect).get_center()).distance_to(c) < apart_min * 0.5:
				apart = false
		if apart:
			var room := _rescue_room(hid)
			rescue.append({"house": hid, "pos": _hide_spot(room, hid), "room": room, "ring": 3, "dist": c.distance_to(start_c)})


## Where a survivor hides in their room: the free tile farthest from every doorway of the house, a corner by preference (one who has barred themselves in keeps clear of the
## way in: not in the line of the front door, where the avatar walks in and the dead stand). The middle of the room (`_free_spot`) when the room has no free tile.
func _hide_spot(room: int, house_id: int) -> Vector2:
	var rr: Rect2i = _rooms[room].rect
	var best := _free_spot(room)
	var best_score := -INF
	var ways: Array = []
	for d in _houses[house_id].doors:
		for t in d.tiles:
			ways.append(Vector2(float(t.x) + 0.5, float(t.y) + 0.5))
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if _solid[y * _size + x] != 0:
				continue
			var at := Vector2(float(x) + 0.5, float(y) + 0.5)
			var near := INF
			for w in ways:
				near = minf(near, at.distance_to(w))
			var corners := 0
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _solid[(y + dv.y) * _size + (x + dv.x)] != 0:
					corners += 1
			var score := (near if near < INF else 0.0) + 0.4 * float(corners)
			if score > best_score:
				best_score = score
				best = at
	return best


## The dead as data records: about 60% in or beside the houses, 40% in the streets in loose groups; a few in each candidate (the best four or five, the middle one three or four, the poor
## one two or three, each in a room of its own), a guard of two to four in every house of the rescue lists (`rescue`: the houses of every candidate's list, once each). `calm`: the points the
## yards, the streets and the houses round them are kept calm of (the entry and the candidates; a town without an arrival, `legacy`: the start house, as ever).
func _dead(cands: Array, rescue: Array, start_room: int, calm: Array, legacy: bool) -> Array:
	var rng := _rng
	var W := _size
	var H := _size
	var total := int(opts.get("dead", maxi(40, roundi(float(DEAD_TOTAL) * float(_blocks * _blocks) / 36.0))))
	var keep_clear := 22.0 * maxf(float(_size) / float(DEFAULT_SIZE), 0.4)    # (how near the start the yards and the streets hold none)
	var yard_r := keep_clear if legacy else CALM_R + 2.0
	var street_r := keep_clear * 1.2 if legacy else CALM_R + 5.0
	var out: Array = []
	var near_house := roundi(float(total) * DEAD_NEAR_HOUSES)
	var in_street := total - near_house
	var taken := {}
	var is_cand := {}
	for c in cands:
		is_cand[int(c.house)] = true
	var near_calm := func(p: Vector2, r: float) -> bool:
		for cp in calm:
			if Vector2(cp).distance_to(p) < r:
				return true
		return false
	var kinds_for := func(r: float) -> String:
		return "brute" if r < 0.03 else ("runner" if r < 0.15 else "walker")
	var road := int(_tids.ASPHALT)
	var walk := int(_tids.SIDEWALK)
	var floor_tiles: Array = []
	var weights: Array = []
	for h in _houses:
		var tiles: Array = []
		var r: Rect2i = h.rect
		for y in range(r.position.y + 1, r.end.y - 1):
			for x in range(r.position.x + 1, r.end.x - 1):
				if _solid[y * W + x] == 0 and _tile_room[y * W + x] >= 0:
					tiles.append(Vector2i(x, y))
		floor_tiles.append(tiles)
		weights.append(float(tiles.size()) if not is_cand.has(int(h.id)) else 0.0)
	var total_w := 0.0
	for w in weights:
		total_w += float(w)
	var made_in := 0
	var guarded := {}
	for r in rescue:
		guarded[int(r.house)] = true
		total_w -= float(weights[int(r.house)])
		weights[int(r.house)] = 0.0
	# `room` >= 0 puts it in that room, -1 anywhere in the house
	var put_inside := func(hid: int, kind: String, state: String, room: int, avoid: int) -> bool:
		var tiles: Array = floor_tiles[hid]
		if room >= 0:
			tiles = tiles.filter(func(t): return _tile_room[t.y * W + t.x] == room)
		elif avoid >= 0:
			var others: Array = tiles.filter(func(t): return _tile_room[t.y * W + t.x] != avoid)
			if not others.is_empty():
				tiles = others
		if tiles.is_empty():
			return false
		for attempt in 40:
			var tile: Vector2i = tiles[rng.randi() % tiles.size()]
			var p := Vector2(float(tile.x) + rng.randf_range(0.25, 0.75), float(tile.y) + rng.randf_range(0.25, 0.75))
			if Vector2(_houses[hid].door).distance_to(p) < 2.5 or not _spaced(taken, p, 1.6):
				continue
			_take(taken, p)
			out.append({"pos": p, "kind": kind, "state": state, "house": hid, "room": _tile_room[tile.y * W + tile.x], "group": -1})
			return true
		return false
	# the three of the start house, then the guards of the rescue houses: two to four, the first in the room of the survivor (who stands where it is
	# not taken: the survivor's tile is kept clear of them)
	# BIGGER HOUSES: four or five of the start house (clearing it is the first quarter of an hour), each in a room of its own and none in the room the avatar wakes in
	# (ARRIVAL: the same for every candidate, by its tier: the avatar does not wake inside any of them, so no room is spared but the start room of a town without an arrival)
	for c in cands:
		var chid := int(c.house)
		var c_rooms: Array = []
		for ri in _houses[chid].rooms:
			if int(ri) != start_room:
				c_rooms.append(int(ri))
		for i in range(c_rooms.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = c_rooms[i]
			c_rooms[i] = c_rooms[j]
			c_rooms[j] = tmp
		var c_want := 0
		match String(c.tier):
			"ok":
				c_want = 3 + (1 if rng.randf() < 0.5 else 0)
			"poor":
				c_want = 2 + (1 if rng.randf() < 0.4 else 0)
			_:
				c_want = 4 + (1 if rng.randf() < 0.45 else 0)
		var c_got := 0
		for ri in c_rooms:
			if c_got >= c_want:
				break
			if put_inside.call(chid, "walker", "still", int(ri), -1):
				c_got += 1
				made_in += 1
	for r in rescue:
		_take(taken, Vector2(r.pos))
	for r in rescue:
		var got_g := 0
		var in_room_ok := false
		for k in 2 + rng.randi() % 4:
			var in_room: int = int(r.room) if k == 0 else -1
			if put_inside.call(int(r.house), "walker" if rng.randf() < 0.85 else "runner", "still", in_room, int(r.room)):
				made_in += 1
				got_g += 1
				in_room_ok = in_room_ok or k == 0
		# (ARRIVAL: a rescue house has a dead one in the survivor's room and two or more in all: the one of the room is tried again on the middle of a free tile of it, a tile or more from
		# the survivor, and the others anywhere in the house)
		if not in_room_ok:
			for t in _rescue_room_tiles(int(r.room)):
				var q := Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
				if q.distance_to(Vector2(r.pos)) < 1.0 or Vector2(_houses[int(r.house)].door).distance_to(q) < 1.2 or not _spaced(taken, q, 0.9):
					continue
				_take(taken, q)
				out.append({"pos": q, "kind": "walker", "state": "still", "house": int(r.house), "room": int(r.room), "group": -1})
				made_in += 1
				got_g += 1
				break
		var tries_g := 0
		while got_g < 2 and tries_g < 6:
			tries_g += 1
			if put_inside.call(int(r.house), "walker", "still", -1, int(r.room)):
				made_in += 1
				got_g += 1
	# TOWNGEN: the dead of the buildings, a few in each by its kind (a house one to three or four, a block of flats or a shop more, a warehouse or the supermarket most), fewer
	# near the start (a calm part of the town), the odd brute in a big one
	var guard := 0
	var scale_in := float(total) / float(DEAD_TOTAL)
	for hi in _houses.size():
		if is_cand.has(hi) or guarded.has(hi) or floor_tiles[hi].is_empty():
			continue
		var hd: Dictionary = _houses[hi]
		var rg: Array = DEAD_BY_KIND.get(String(hd.kind), Plans.Recipes.dead_range(String(hd.kind)))
		var n := rng.randi_range(int(rg[0]), int(rg[1]))
		var calm_house: bool = near_calm.call(Vector2(Rect2i(hd.rect).get_center()), 20.0)
		if calm_house:
			n = roundi(float(n) * 0.35)
		elif scale_in < 1.0:
			n = roundi(float(n) * maxf(scale_in, 0.4))
		for k in n:
			var kd: String = kinds_for.call(rng.randf())
			if k == 0 and n >= 5 and rng.randf() < 0.2:
				kd = "brute"
			# (a house in the calm parts keeps its dead standing: none walks out of it in front of the avatar)
			if put_inside.call(hi, kd, "still" if (rng.randf() < 0.85 or (calm_house and not legacy)) else "wander", -1, -1):
				made_in += 1
	# beside the houses: grass of the lots, front and back
	var yard_n := roundi(float(total) * 0.12)
	var made := 0
	guard = 0
	while made < yard_n and guard < yard_n * 80:
		guard += 1
		var hi := rng.randi() % _houses.size()
		if is_cand.has(hi) or guarded.has(hi):
			continue
		var lot: Rect2i = _houses[hi].lot
		var x := rng.randi_range(lot.position.x, lot.end.x - 1)
		var y := rng.randi_range(lot.position.y, lot.end.y - 1)
		if _solid[y * W + x] != 0 or _terrain[y * W + x] != int(_tids.GRASS) or _tile_house[y * W + x] >= 0:
			continue
		var p := Vector2(float(x) + rng.randf_range(0.25, 0.75), float(y) + rng.randf_range(0.25, 0.75))
		if near_calm.call(p, yard_r) or not _spaced(taken, p, 1.6):
			continue
		_take(taken, p)
		out.append({"pos": p, "kind": kinds_for.call(rng.randf()), "state": "still" if rng.randf() < 0.8 else "wander", "house": hi, "room": -1, "group": -1})
		made += 1
	# the streets: loose groups of one to four on the paving (the rest of the total)
	in_street = maxi(0, total - made_in - made)
	made = 0
	var group := 0
	guard = 0
	while made < in_street and guard < 4000:
		guard += 1
		var cx := rng.randi_range(EDGE + 4, W - EDGE - 5)
		var cy := rng.randi_range(EDGE + 4, H - EDGE - 5)
		var ci := cy * W + cx
		if (_terrain[ci] != road and _terrain[ci] != walk) or _solid[ci] != 0:
			continue
		var centre := Vector2(float(cx) + 0.5, float(cy) + 0.5)
		if near_calm.call(centre, street_r):
			continue
		var n := mini(rng.randi_range(1, 4), in_street - made)
		var got := 0
		var t2 := 0
		while got < n and t2 < 60:
			t2 += 1
			var p := centre + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
			var pi := floori(p.y) * W + floori(p.x)
			if pi < 0 or pi >= W * H or _solid[pi] != 0 or (_terrain[pi] != road and _terrain[pi] != walk):
				continue
			if not _spaced(taken, p, 1.2):
				continue
			_take(taken, p)
			out.append({"pos": p, "kind": kinds_for.call(rng.randf()), "state": "still" if rng.randf() < 0.6 else "wander", "house": -1, "room": -1, "group": group})
			got += 1
		made += got
		group += 1
	return out


static func _spaced(taken: Dictionary, p: Vector2, d: float) -> bool:
	var gx := floori(p.x / 2.0)
	var gy := floori(p.y / 2.0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Array = taken.get(Vector2i(gx + dx, gy + dy), [])
			for q in cell:
				if Vector2(q).distance_to(p) < d:
					return false
	return true


static func _take(taken: Dictionary, p: Vector2) -> void:
	var key := Vector2i(floori(p.x / 2.0), floori(p.y / 2.0))
	if not taken.has(key):
		taken[key] = []
	taken[key].append(p)


# ----------------------------------------------------------------------- helpers --

## The house whose walls hold a tile (point in tiles), or -1.
static func house_at(town: Dictionary, x: float, y: float) -> int:
	var tx := floori(x)
	var ty := floori(y)
	var w := int(town.size.x)
	if tx < 0 or ty < 0 or tx >= w or ty >= int(town.size.y):
		return -1
	return int(town.tile_house[ty * w + tx])


## The room (index) whose floor holds a point, or -1 (a wall, a doorway, outside).
static func room_at(town: Dictionary, x: float, y: float) -> int:
	var tx := floori(x)
	var ty := floori(y)
	var w := int(town.size.x)
	if tx < 0 or ty < 0 or tx >= w or ty >= int(town.size.y):
		return -1
	return int(town.tile_room[ty * w + tx])


## A number that is the same for the same town: the terrain, the houses, the containers and the dead (a test pins it for a seed).
static func digest(town: Dictionary) -> int:
	var h := 2166136261
	for v in town.data.terrain:
		h = ((h ^ int(v)) * 16777619) & 0xFFFFFFFF
	for hs in town.houses:
		var r: Rect2i = hs.rect
		for v in [r.position.x, r.position.y, r.size.x, r.size.y, hs.doors.size(), hs.rooms.size()]:
			h = ((h ^ int(v)) * 16777619) & 0xFFFFFFFF
	for c in town.containers:
		h = ((h ^ roundi(float(c.pos.x) * 4.0)) * 16777619) & 0xFFFFFFFF
		h = ((h ^ roundi(float(c.pos.y) * 4.0)) * 16777619) & 0xFFFFFFFF
	for dd in town.dead:
		h = ((h ^ roundi(float(dd.pos.x) * 100.0)) * 16777619) & 0xFFFFFFFF
		h = ((h ^ roundi(float(dd.pos.y) * 100.0)) * 16777619) & 0xFFFFFFFF
	return h
