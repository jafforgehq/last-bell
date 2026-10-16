## RAID SITES (task V, 2026-10-16): a raid place of the destination map looks and plays like its name. Every place of `places` in assets/data/prison_raids.json whose `layout` is one of
## LAYOUTS gets a hand-laid 64 x 64 map made here instead of the generator's four-block town: the port (a quay with the sea along the east edge, a ship's hull, three cranes, rows of container
## stacks as cover and loot, two warehouses), the airport (a runway and a taxiway across the north, an apron with two airliners and fuel trucks, a terminal with three gates, two hangars with
## a small plane in each), the stadium (an oval bowl: the outer wall with four gates, a concourse with food stalls, a ring of seats with aisles, the pitch with a crowd of the dead), the
## hospital (one big building of wards, corridors, a pharmacy, a theatre and a morgue, ambulances at the door), the supermarket (a big store with aisles of shelves and a car park), the police
## station (cells, an armoury, a locker room, patrol cars, sandbags at the door) and the industrial yard (a fenced yard, three sheds, machinery and scrap piles). The suburb ("houses") and the
## plain town keep the generator's streets.
## PATTERN: like the prison compound (prison_base.gd), the map is a TownGen-shaped Dictionary (the same keys: data, houses, rooms, containers, dead, entry, tile_house, tile_room...), so the
## town's World, the real Sim (search, dormant dead, path finding), the roofs, the loot post-pass (prison_loot.gd) and every raid module run it unchanged. The buildings are real houses with rooms,
## doors and windows (`_bldg`); the furniture is the town's kit (`_furn`: the props of TownKit.layouts(), the kit fields as the generator gives them). What the kit has no picture for (water,
## runway marks, cranes, planes, container stacks, stands, vehicles of a kind) is code-drawn in the RimWorld flat style with a dark outline by `paint` (two layers: the ground, under the people,
## and `high`, over them: the crane booms) from the list `site.props`, and stands on solid tiles. Outdoor loot (a container stack, a fuel truck, a food stall, an ambulance) is a container with
## `car: true` (no house), searched like a street car (scripts/town/houses.gd puts it beside the cars). Each building's place type, name and hint are data (`places.<id>.buildings`).
## A seed moves the details (which stacks are open, the cars, the furniture's variants, where the dead stand), never the plan.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const TownKit := preload("res://scripts/town/town_kit.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const Canvas := preload("res://scripts/raid/site_canvas.gd")

const LAYOUTS := ["quay", "apron", "stands", "wards", "shops", "armoury", "yard"]
const W := 64
const H := 64
const TILE := 64.0
# terrain ids (map.json terrainTypes and the town kit's walls)
const T_ASPHALT := 1
const T_SIDEWALK := 2
const T_GRASS := 4
const T_LINO := 6
const T_TERRAZZO := 7
const T_WOOD := 8
const T_KITCHEN := 11
const T_CONCRETE := 12
const T_DIRT := 13
const T_BRICK := 20
const T_PLASTER := 21
const T_METAL := 22
const T_DOOR := 23
## The kit's ground codes (TownArt.GROUNDS index + 1) and the terrain each floor stands on.
const GR := {"lawn": 1, "asphalt": 2, "sidewalk": 3, "dirt": 4, "gravel": 5, "wood": 6, "hall": 7, "kitchen": 8, "carpet": 9, "bath": 10}
const FLOOR_T := {"lawn": T_GRASS, "asphalt": T_ASPHALT, "sidewalk": T_CONCRETE, "dirt": T_DIRT, "gravel": T_DIRT, "wood": T_WOOD, "hall": T_TERRAZZO, "kitchen": T_KITCHEN, "carpet": T_WOOD, "bath": T_LINO}
const L_CHAIN := 3
const L_HEDGE := 5
## The minimap's own colours of the code-drawn ground (`data.site_mini`): water, runway, pitch, seats.
const MINI := {1: Color(0.16, 0.32, 0.5), 2: Color(0.16, 0.16, 0.18), 3: Color(0.25, 0.45, 0.2), 4: Color(0.42, 0.3, 0.3)}

static var _props := {}
static var _tids := {}

var lay := ""
var seed_i := 1
var rng := RandomNumberGenerator.new()
var bcfg := {}
var terrain := PackedInt32Array()
var solid := PackedByteArray()
var low := PackedByteArray()
var keep := PackedByteArray()
var kg := PackedByteArray()
var kw := PackedByteArray()
var kl := PackedByteArray()
var mini := PackedByteArray()
var th := PackedInt32Array()
var tr := PackedInt32Array()
var objects: Array = []
var trees: Array = []
var houses: Array = []
var rooms: Array = []
var rooms_dict := {}
var conts: Array = []
var dead: Array = []
var windows: Array = []
var props: Array = []
var groups: Array = []
var entry := Vector2(4.5, 31.5)
var entry_road := Rect2i(0, 30, 12, 4)
var exit_at := Vector2(59.5, 31.5)
var _cv
var _kit


## The site of a place ({} when its layout is not one of LAYOUTS: the caller makes the generator's town). `place` is the place's entry of the data (prison_loot.gd `place_cfg`).
static func make(seed_in: int, place: Dictionary) -> Dictionary:
	var l := String(place.get("layout", ""))
	if not LAYOUTS.has(l):
		return {}
	var s = (load("res://scripts/prison/prison_site.gd") as GDScript).new()
	return s._build(seed_in, l, place)


func _i(x: int, y: int) -> int:
	return y * W + x


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func _build(seed_in: int, l: String, place: Dictionary) -> Dictionary:
	lay = l
	seed_i = seed_in
	rng.seed = seed_in * 7919 + 4111
	bcfg = place.get("buildings", {})
	if _props.is_empty():
		var lays: Dictionary = TownKit.layouts()
		_props = lays.props
		var base: Dictionary = GD.load_all()
		for k in base.terrainTypes:
			_tids[k] = int(base.terrainTypes[k].id)
		for k in lays.terrain:
			_tids[k] = int(lays.terrain[k].id)
	_cv = Canvas.new()
	_cv.setup(8, 8, seed_in + 5, _props, _tids, {})
	_cv.size_by_table = true
	_kit = TownKit.new()
	solid.resize(W * H)
	low.resize(W * H)
	keep.resize(W * H)
	kg.resize(W * H)
	kw.resize(W * H)
	kl.resize(W * H)
	mini.resize(W * H)
	terrain.resize(W * H)
	terrain.fill(T_GRASS)
	kg.fill(GR.lawn)
	th.resize(W * H)
	th.fill(-1)
	tr.resize(W * H)
	tr.fill(-1)
	match lay:
		"quay":
			_port()
		"apron":
			_airport()
		"stands":
			_stadium()
		"wards":
			_hospital()
		"shops":
			_supermarket()
		"armoury":
			_police()
		"yard":
			_industrial()
	_border()
	_trees()
	_finish_containers()
	_reach()
	return _result()


# ------------------------------------------------------------------ painting the grids --

func _put(x: int, y: int, t: int, g: int, s: int = 0) -> void:
	if not _in(x, y):
		return
	var i := _i(x, y)
	terrain[i] = t
	kg[i] = g
	solid[i] = s
	low[i] = 0
	kw[i] = 0
	kl[i] = 0


func _fill(r: Rect2i, ground: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(x, y, int(FLOOR_T[ground]), int(GR[ground]))


## Solid ground (a prop drawn by `paint` stands on it); `is_low`: shots and the dead's eye go over it (water, seats).
func _shut(r: Rect2i, is_low: bool = false) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _in(x, y):
				solid[_i(x, y)] = 1
				low[_i(x, y)] = 1 if is_low else 0


func _fence(x: int, y: int, line: int = L_CHAIN) -> void:
	if not _in(x, y) or th[_i(x, y)] >= 0:
		return
	var g := kg[_i(x, y)]
	_put(x, y, T_METAL, g, 1)
	kl[_i(x, y)] = line


func _fence_rect(r: Rect2i, gaps: Array, line: int = L_CHAIN) -> void:
	for x in range(r.position.x, r.end.x):
		for y in [r.position.y, r.end.y - 1]:
			if not _gap(gaps, x, y):
				_fence(x, y, line)
	for y in range(r.position.y, r.end.y):
		for x in [r.position.x, r.end.x - 1]:
			if not _gap(gaps, x, y):
				_fence(x, y, line)


func _gap(gaps: Array, x: int, y: int) -> bool:
	for g in gaps:
		if Rect2i(g).has_point(Vector2i(x, y)):
			return true
	return false


func _prop(k: String, r: Rect2, extra: Dictionary = {}) -> Dictionary:
	var p := {"k": k, "r": r}
	p.merge(extra)
	props.append(p)
	return p


## The map's edge: a hedge round it but on the roads and the water.
func _border() -> void:
	for x in W:
		for y in [0, H - 1]:
			if terrain[_i(x, y)] != T_ASPHALT and mini[_i(x, y)] != 1:
				_fence(x, y, L_HEDGE)
	for y in H:
		for x in [0, W - 1]:
			if terrain[_i(x, y)] != T_ASPHALT and mini[_i(x, y)] != 1:
				_fence(x, y, L_HEDGE)


## Trees on the open lawn, two tiles from anything solid and from the paths.
func _trees() -> void:
	var n := 0
	for k in 400:
		if n >= 26:
			break
		var x := rng.randi_range(2, W - 3)
		var y := rng.randi_range(2, H - 3)
		var ok := true
		for yy in range(y - 2, y + 3):
			for xx in range(x - 2, x + 3):
				var i := _i(xx, yy)
				if terrain[i] != T_GRASS or solid[i] != 0 or keep[i] != 0 or th[i] >= 0 or mini[i] != 0:
					ok = false
		if not ok or Vector2(x, y).distance_to(entry) < 8.0 or Vector2(x, y).distance_to(exit_at) < 5.0:
			continue
		var v: int = [24, 24, 22, 23, 21, 0, 2][rng.randi() % 7]
		trees.append({"x": float(x) + 0.5, "y": float(y) + 0.55, "variant": v % 3, "file": "res://assets/trees/tree_%d.png" % v})
		solid[_i(x, y)] = 1
		n += 1


func _road(r: Rect2i) -> void:
	_fill(r, "asphalt")
	_keep(r)


func _keep(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _in(x, y):
				keep[_i(x, y)] = 1


func _entry(r: Rect2i, at: Vector2) -> void:
	entry_road = r
	_road(r)
	entry = at


# ------------------------------------------------------------------ buildings --

## A building: `r` its outer walls, `rms` its rooms [[Rect2i floor, name, ground, place type or "", label or ""], ...] (separated by one tile of wall), `doors` the doorways (Rect2i cut through
## a wall, outer or inner). `key` names its entry of the place's `buildings` (type, name, hint). Returns the house id.
func _bldg(key: String, r: Rect2i, rms: Array, doors: Array, mat: int = 1) -> int:
	var hid := houses.size()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			_put(x, y, T_BRICK if edge else T_PLASTER, GR.hall, 1)
			kw[_i(x, y)] = mat if edge else 7
			th[_i(x, y)] = hid
	var room_ids: Array = []
	for rm in rms:
		var rr: Rect2i = rm[0]
		var ri := rooms.size()
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				_put(x, y, int(FLOOR_T[String(rm[2])]), int(GR[String(rm[2])]))
				tr[_i(x, y)] = ri
		var nm := String(rm[1])
		var rid := "h%d:%s" % [hid, nm]
		var k := 2
		while rooms_dict.has(rid):
			rid = "h%d:%s_%d" % [hid, nm, k]
			k += 1
		var room := {"id": rid, "house": hid, "name": nm, "rect": rr}
		if rm.size() > 3 and String(rm[3]) != "":
			var bc: Dictionary = bcfg.get(String(rm[3]), {})
			room["ptype"] = String(bc.get("type", "house"))
			room["label"] = String(bc.get("name", nm.capitalize()))
			room["hint"] = String(bc.get("hint", ""))
		rooms.append(room)
		rooms_dict[rid] = [rr.position.x, rr.position.y, rr.end.x, rr.end.y]
		room_ids.append(ri)
	var drs: Array = []
	var front := Vector2i(-1, -1)
	var side_f := "S"
	for d in doors:
		var dr: Rect2i = d
		var tiles: Array = []
		for y in range(dr.position.y, dr.end.y):
			for x in range(dr.position.x, dr.end.x):
				_put(x, y, T_DOOR, GR.wood)
				th[_i(x, y)] = hid
				tiles.append(Vector2i(x, y))
		var horiz := dr.size.x > dr.size.y or (dr.size.x == dr.size.y and _wallish(dr.position.x - 1, dr.position.y) and _wallish(dr.end.x, dr.position.y))
		var f: Vector2i = tiles[0]
		var a := f + (Vector2i(0, -1) if horiz else Vector2i(-1, 0))
		var b := f + (Vector2i(0, 1) if horiz else Vector2i(1, 0))
		var rec := {"tiles": tiles, "exterior": true, "side": "", "out": a, "in": b}
		if not r.has_point(a):
			rec.side = "N" if horiz else "W"
		elif not r.has_point(b):
			rec.side = "S" if horiz else "E"
			rec.out = b
			rec["in"] = a
		else:
			rec.exterior = false
			rec.side = "H" if horiz else "V"
		for t in tiles:    # (no furniture in a doorway's way, inside or out)
			for q in [Vector2i(t) + (Vector2i(0, -1) if horiz else Vector2i(-1, 0)), Vector2i(t) + (Vector2i(0, 1) if horiz else Vector2i(1, 0))]:
				if _in(q.x, q.y):
					keep[_i(q.x, q.y)] = 1
		if bool(rec.exterior) and front.x < 0:
			front = rec.out
			side_f = String(rec.side)
		drs.append(rec)
	var bc2: Dictionary = bcfg.get(key, {})
	var house := {
		"id": hid, "kind": key, "var": key, "facade": {}, "address": String(bc2.get("name", key.capitalize())), "block": Vector2i(0, 0), "rect": r, "parts": [r], "lot": r,
		"front": "N" if side_f == "N" else "S", "fenced": false, "door": front if front.x >= 0 else Vector2i(r.get_center()), "doors": drs, "rooms": room_ids, "containers": [], "dead": [],
		"district": "industrial", "type": "commercial", "yard": r, "front_yard": Rect2i(), "back_yard": Rect2i(), "yard_type": "bare", "wall": String(TownArt.WALL_MATS[mat]),
		"roof": hid % 3, "state": "intact", "boarded": false, "barricaded": false, "drive": Rect2i(), "landmark": "", "street": "", "number": hid + 1, "main": true,
		"ptype": String(bc2.get("type", "house")), "label": String(bc2.get("name", key.capitalize())), "hint": String(bc2.get("hint", "")),
	}
	houses.append(house)
	_windows(r, hid)
	return hid


func _wallish(x: int, y: int) -> bool:
	if not _in(x, y):
		return false
	var t := terrain[_i(x, y)]
	return t == T_BRICK or t == T_PLASTER or t == T_DOOR


## Windows in the outer walls, every four tiles, not at a door, a corner or where a wall inside meets the outer one.
func _windows(r: Rect2i, hid: int) -> void:
	for side in 4:
		var horiz := side < 2
		var span := r.size.x if horiz else r.size.y
		var pos := 2
		while pos < span - 2:
			var x := r.position.x + pos if horiz else (r.position.x if side == 2 else r.end.x - 1)
			var y := (r.position.y if side == 0 else r.end.y - 1) if horiz else r.position.y + pos
			var ok := true
			for k in range(-1, 2):
				var q := Vector2i(x + k, y) if horiz else Vector2i(x, y + k)
				if terrain[_i(q.x, q.y)] != T_BRICK:
					ok = false
			var inward := Vector2i(x, y + (1 if side == 0 else -1)) if horiz else Vector2i(x + (1 if side == 2 else -1), y)
			if terrain[_i(inward.x, inward.y)] == T_PLASTER or terrain[_i(inward.x, inward.y)] == T_BRICK:
				ok = false
			if ok:
				windows.append({"x": x, "y": y, "orient": "h" if horiz else "v", "state": "intact" if rng.randf() < 0.7 else ("broken" if rng.randf() < 0.6 else "boarded"), "variant": rng.randi_range(0, 1), "bar": false, "house": hid})
			pos += 4


# ------------------------------------------------------------------ furniture and loot --

## One thing of the kit with the middle of its footprint at (cx, cy) (facing "s", "n", "e", "w": a thing that is not square faces north or south only). `cont`: it is a container of that
## kind ("" for none). Returns the object, or {} when the kit has no such thing or its tiles are taken (by a wall, another thing or the way to a door).
func _furn(kind: String, cx: float, cy: float, facing: String = "s", cont: String = "", force: bool = false) -> Dictionary:
	if not _props.has(kind):
		return {}
	var p: Dictionary = _props[kind]
	var fp := Vector2i(int(p.tiles[0]), int(p.tiles[1]))
	var w := fp.x
	var h := fp.y
	if facing == "e" or facing == "w":
		if w != h:
			facing = "s"
	var x0 := int(floor(cx - float(w) / 2.0 + 0.01))
	var y0 := int(floor(cy - float(h) / 2.0 + 0.01))
	var is_solid := bool(p.get("solid", true))
	for yy in range(y0, y0 + h):
		for xx in range(x0, x0 + w):
			if not _in(xx, yy) or solid[_i(xx, yy)] != 0 or terrain[_i(xx, yy)] == T_DOOR:
				return {}
			if is_solid and keep[_i(xx, yy)] != 0 and not force:
				return {}
	var files: Array = p.files
	var o = _cv._add_obj(kind, p, cx, cy, w, h, String(files[rng.randi() % files.size()]), is_solid, {})
	if o == null:
		return {}
	_cv.objects.clear()
	if p.has("kit"):
		_kit.kit_set(o, p, rng)
		if not p.has("orient") and int(o.layer) != 1:
			o["facing"] = facing
	o["id"] = objects.size()
	o["order"] = objects.size()
	var hid := th[_i(int(floor(cx)), int(floor(cy)))]
	if hid >= 0:
		o["in"] = hid
	objects.append(o)
	if is_solid:
		for yy in range(y0, y0 + h):
			for xx in range(x0, x0 + w):
				solid[_i(xx, yy)] = 1
				if kind != "car_h" and kind != "car_v" and kind != "car_wreck" and not ["wardrobe", "shop_shelf", "shelf_tins", "bookshelf", "tool_chest", "fridge", "cooler"].has(kind):
					low[_i(xx, yy)] = 1    # (a bed, a counter, a crate: shots go over it)
	if cont != "":
		var room := tr[_i(int(floor(cx)), int(floor(cy)))]
		conts.append({"house": hid, "room": room, "at": Vector2(cx, cy), "kind": cont, "loot": {}, "search_s": 4.0, "fp": Rect2i(x0, y0, w, h)})
	return o


## A row of things along x (n of them `step` apart from x0), every `every`-th a container.
func _row(kind: String, x0: float, y: float, n: int, step: float, facing: String = "s", cont: String = "", every: int = 1) -> void:
	for k in n:
		_furn(kind, x0 + float(k) * step, y, facing, cont if cont != "" and k % every == 0 else "")


## A container out in the open (a stack, a truck, a stall): code-drawn (`paint` kind `pk`), solid, searched like a car. `name` is what the prompt says ("Search the fuel truck").
func _yard(name: String, r: Rect2i, ptype: String, pk: String, extra: Dictionary = {}) -> void:
	_shut(r)
	var p := _prop(pk, Rect2(r), extra)
	p["name"] = name
	if ptype != "":
		conts.append({"house": -1, "room": -1, "at": Vector2(r.get_center()), "kind": name.replace(" ", "_"), "name": name, "loot": {}, "search_s": 4.0, "car": true, "rect": r, "ptype": ptype,
			"obj": -1, "piece": "", "fp": r})


## A free tile beside a footprint to stand on and search it: in the same room for a thing inside, outside every house for one in the open; the side it faces first. (-1, -1) for none.
func _stand(c: Dictionary) -> Vector2:
	var fp: Rect2i = c.fp
	var best := Vector2(-1, -1)
	var bs := 1.0e9
	var at: Vector2 = c.at
	for y in range(fp.position.y - 1, fp.end.y + 1):
		for x in range(fp.position.x - 1, fp.end.x + 1):
			if fp.has_point(Vector2i(x, y)) or not _in(x, y):
				continue
			if (x == fp.position.x - 1 or x == fp.end.x) and (y == fp.position.y - 1 or y == fp.end.y):
				continue
			var i := _i(x, y)
			if solid[i] != 0 or terrain[i] == T_DOOR:
				continue
			if int(c.house) >= 0 and tr[i] != int(c.room):
				continue
			if int(c.house) < 0 and th[i] >= 0:
				continue
			var sc := Vector2(x + 0.5, y + 0.5).distance_to(at) + (0.0 if y >= fp.end.y else 0.4)
			if sc < bs:
				bs = sc
				best = Vector2(x + 0.5, y + 0.5)
	return best


func _finish_containers() -> void:
	var out: Array = []
	var per := {}
	var yard_n := 0
	for c in conts:
		var st := _stand(c)
		if st.x < 0.0:
			continue
		c["pos"] = st
		var hid := int(c.house)
		if hid >= 0:
			var n := int(per.get(hid, 0))
			per[hid] = n + 1
			c["id"] = "h%dc%d" % [hid, n]
			(houses[hid].containers as Array).append(c.id)
		else:
			c["id"] = "yd%d" % yard_n
			yard_n += 1
		out.append(c)
	conts = out


## Every container and both pickup points reachable on foot from the entry: the ones that are not are dropped (a check, `unreachable` lists them), the pickup point moved to the nearest reached tile.
func _reach() -> void:
	var seen := flood(solid, entry)
	var keep_c: Array = []
	for c in conts:
		var p: Vector2 = c.pos
		if seen[_i(int(p.x), int(p.y))] != 0:
			keep_c.append(c)
		else:
			var hid := int(c.house)
			if hid >= 0:
				(houses[hid].containers as Array).erase(c.id)
	conts = keep_c
	if seen[_i(int(exit_at.x), int(exit_at.y))] == 0:
		var best := exit_at
		var bd := 1.0e9
		for y in H:
			for x in W:
				if seen[_i(x, y)] != 0 and th[_i(x, y)] < 0 and Vector2(x + 0.5, y + 0.5).distance_to(exit_at) < bd:
					bd = Vector2(x + 0.5, y + 0.5).distance_to(exit_at)
					best = Vector2(x + 0.5, y + 0.5)
		exit_at = best


## The tiles reachable on foot from `from` (4 ways) over a solid grid of W x H.
static func flood(grid, from: Vector2) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(W * H)
	var s := int(from.y) * W + int(from.x)
	if s < 0 or s >= W * H or int(grid[s]) != 0:
		return seen
	var q := PackedInt32Array([s])
	seen[s] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % W
		var y := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if seen[j] == 0 and int(grid[j]) == 0:
				seen[j] = 1
				q.append(j)
	return seen


## The check of a made site (`town` = a result of `make`): [what is not reachable from the entry]: containers by id, "exit". Empty when all is well.
static func unreachable(town: Dictionary) -> Array:
	var out: Array = []
	var seen := flood(town.data.solidP, Vector2(town.entry.pos))
	for c in town.containers:
		var p: Vector2 = c.pos
		if seen[int(p.y) * W + int(p.x)] == 0:
			out.append(String(c.id))
	var ex: Vector2 = town.site.exit
	if seen[int(ex.y) * W + int(ex.x)] == 0:
		out.append("exit")
	return out


# ------------------------------------------------------------------ the dead --

## `n` dead on free tiles of `r` (spaced), still or wandering; `kinds` weights [walker, runner, brute].
func _dead(r: Rect2i, n: int, state: String = "still", runner: float = 0.08, brute: float = 0.03) -> void:
	var placed := 0
	for k in n * 30:
		if placed >= n:
			break
		var x := rng.randi_range(r.position.x, r.end.x - 1)
		var y := rng.randi_range(r.position.y, r.end.y - 1)
		if not _in(x, y):
			continue
		var i := _i(x, y)
		if solid[i] != 0 or terrain[i] == T_DOOR or Vector2(x, y).distance_to(entry) < 10.0:
			continue
		var p := Vector2(x + rng.randf_range(0.3, 0.7), y + rng.randf_range(0.3, 0.7))
		var near := false
		for d in dead:
			if Vector2(d.pos).distance_to(p) < 1.2:
				near = true
				break
		if near:
			continue
		var u := rng.randf()
		var kind := "runner" if u < runner else ("brute" if u < runner + brute else "walker")
		dead.append({"pos": p, "kind": kind, "state": state if state != "mix" else ("still" if rng.randf() < 0.5 else "wander"), "house": th[i], "room": tr[i], "group": -1})
		placed += 1


## The dead of every room of a house: about one for each `per` tiles of floor.
func _dead_rooms(hid: int, per: float, state: String = "still") -> void:
	for ri in houses[hid].rooms:
		var rr: Rect2i = rooms[ri].rect
		_dead(rr, int(round(float(rr.size.x * rr.size.y) / per)), state)


# ------------------------------------------------------------------ the result --

func _result() -> Dictionary:
	var d: Dictionary = GD.load_all().duplicate(false)
	var tt: Dictionary = (d.terrainTypes as Dictionary).duplicate(true)
	for k in TownKit.layouts().terrain:
		tt[k] = {"id": int(TownKit.layouts().terrain[k].id), "file": String(TownKit.layouts().terrain[k].file)}
	d["W"] = W
	d["H"] = H
	d["terrainTypes"] = tt
	d["terrain"] = Array(terrain)
	d["solidZ"] = Array(solid)
	d["solidP"] = Array(solid)
	d["shot_low"] = low
	var zeros: Array = []
	zeros.resize(W * H)
	zeros.fill(0)
	d["wall"] = zeros
	d["objects"] = objects
	d["marks"] = []
	d["walls"] = []
	d["segments"] = []
	d["trees"] = trees
	d["lights"] = []
	d["rooms"] = rooms_dict
	d["spawns"] = [[exit_at.x, exit_at.y]]
	d["yard"] = [1, 1, W - 1, H - 1]
	d["people"] = []
	d["bonds"] = []
	d["site_mini"] = mini
	var hr: Array = []
	for h in houses:
		var r: Rect2i = h.rect
		hr.append([r.position.x, r.position.y, r.size.x, r.size.y])
	d["kit"] = {"ground": kg, "wall": kw, "line": kl, "windows": windows, "gates": [], "houses": hr}
	d["workshop"] = {"x": 0.0, "y": 0.0, "what": "Out"}
	for c in conts:
		c.erase("fp")
	return {
		"seed": seed_i, "version": 1, "size": Vector2i(W, H), "data": d, "houses": houses, "rooms": rooms, "containers": conts, "dead": dead,
		"start": {"house": 0, "pos": entry, "room": -1, "ring": {}},
		"entry": {"pos": entry, "face": "E", "road": entry_road, "label": "The way in", "sign": Vector2(-1, -1), "arrows": []},
		"candidates": [], "rescue_for": {}, "rescue": [], "tile_house": th, "tile_room": tr, "fields": [], "lots": [], "landmarks": [],
		"streets": {"pitch": 32, "block": 28, "road": 4, "names_x": [], "names_y": [], "roads": [], "avenue": -1},
		"site": {"layout": lay, "props": props, "groups": groups, "exit": exit_at},
	}


# ================================================================== THE PLACES ==

## THE PORT: the sea along the east edge with a ship's hull, the quay with three cranes, the container yard (rows of stacks with two-tile aisles, about a third of them open), two warehouses on
## the west, a dock office and a fuel depot on the quay. In from the west road, out at the north end of the quay.
func _port() -> void:
	_fill(Rect2i(12, 1, 24, 62), "asphalt")
	_fill(Rect2i(36, 1, 15, 62), "sidewalk")
	_entry(Rect2i(0, 30, 36, 4), Vector2(4.5, 31.5))
	for y in H:
		for x in range(51, W):
			_put(x, y, T_DIRT, GR.gravel, 1)
			low[_i(x, y)] = 1
			mini[_i(x, y)] = 1
	_prop("water", Rect2(51, -14, 27, 92))
	_prop("hull", Rect2(54.6, 4.0, 7.6, 44.0))
	_prop("quay", Rect2(50.4, 0, 0.6, 64))
	for cy in [5, 21, 41]:
		for q in [Vector2i(38, cy), Vector2i(48, cy), Vector2i(38, cy + 5), Vector2i(48, cy + 5)]:
			_shut(Rect2i(q, Vector2i.ONE))
		_prop("crane", Rect2(37.6, cy - 0.4, 11.8, 6.8), {"high": true})
	# the stacks
	var cols := [13, 21, 29]
	var rows := [2, 6, 10, 14, 18, 22, 26, 36, 40, 44, 48, 52, 56]
	var cols_pal := [Color(0.72, 0.24, 0.2), Color(0.2, 0.42, 0.66), Color(0.3, 0.55, 0.32), Color(0.85, 0.55, 0.18), Color(0.25, 0.6, 0.62), Color(0.55, 0.55, 0.58)]
	var n := 0
	for y in rows:
		for x in cols:
			if rng.randf() < 0.12:
				continue
			var r := Rect2i(x, y, 6, 2)
			var col: Color = cols_pal[rng.randi() % cols_pal.size()]
			var open := rng.randf() < 0.36
			n += 1
			if open:
				_yard("shipping container", r, "hardware" if n % 2 == 0 else "garage", "stack", {"c": col, "tall": rng.randf() < 0.4, "open": true})
			else:
				_shut(r)
				_prop("stack", Rect2(r), {"c": col, "tall": rng.randf() < 0.5})
	groups.append({"name": String(bcfg.get("stacks", {}).get("name", "Container stacks")), "hint": String(bcfg.get("stacks", {}).get("hint", "")), "type": String(bcfg.get("stacks", {}).get("type", "hardware")), "rect": Rect2(13, 2, 22, 56)})
	# the warehouses
	var w1 := _bldg("warehouse", Rect2i(2, 3, 10, 22), [[Rect2i(3, 4, 8, 14), "warehouse floor", "hall"], [Rect2i(3, 19, 8, 5), "office", "wood"]],
		[Rect2i(11, 8, 1, 4), Rect2i(6, 18, 2, 1), Rect2i(6, 24, 2, 1)], 3)
	var w2 := _bldg("warehouse", Rect2i(2, 38, 10, 22), [[Rect2i(3, 39, 8, 5), "office", "wood"], [Rect2i(3, 45, 8, 14), "warehouse floor", "hall"]],
		[Rect2i(11, 50, 1, 4), Rect2i(6, 44, 2, 1), Rect2i(6, 38, 2, 1)], 3)
	for wy in [[4, 17, 19, 23], [45, 58, 39, 43]]:
		_row("shop_shelf", 4.0, float(wy[0]) + 0.5, 3, 3.0, "s", "shelf", 2)
		_row("crate", 4.5, float(wy[1]) + 0.5, 5, 1.0, "s", "crate", 2)
		_furn("pallet", 8.0, float(wy[0]) + 6.5)
		_furn("crate", 5.5, float(wy[0]) + 8.5, "s", "crate")
		_furn("tool_chest", 9.0, float(wy[0]) + 10.5, "s", "tool_chest")
		_furn("desk", 5.0, float(wy[2]) + 0.5, "s", "desk")
		_furn("wardrobe", 9.0, float(wy[3]) + 0.5, "n", "locker")
	_dead_rooms(w1, 14.0)
	_dead_rooms(w2, 14.0)
	# the dock office and the fuel depot on the quay
	var off := _bldg("dock_office", Rect2i(38, 34, 10, 6), [[Rect2i(39, 35, 8, 4), "dock office", "wood"]], [Rect2i(38, 36, 1, 2)], 2)
	_furn("desk", 41.0, 35.5, "s", "desk")
	_furn("wardrobe", 45.0, 35.5, "s", "locker")
	_furn("tool_chest", 44.0, 38.5, "n", "tool_chest")
	_dead_rooms(off, 12.0)
	var dep := _bldg("depot", Rect2i(38, 51, 8, 6), [[Rect2i(39, 52, 6, 4), "pump room", "hall"]], [Rect2i(41, 51, 2, 1)], 2)
	_furn("tool_chest", 40.0, 55.5, "n", "tool_chest")
	_furn("crate", 43.5, 55.5, "n", "crate")
	_dead_rooms(dep, 12.0)
	for tk in [Rect2i(39, 58, 3, 3), Rect2i(43, 58, 3, 3)]:
		_shut(tk)
		_prop("tank", Rect2(tk))
	_yard("fuel truck", Rect2i(48, 51, 2, 5), "petrol", "fuel_truck")
	_yard("fuel truck", Rect2i(42, 28, 2, 5), "petrol", "fuel_truck")
	for k in 4:
		_furn("car_v" if k % 2 == 0 else "car_h", float(rng.randi_range(39, 46)) + 0.5, float(13 + k * 7) + 0.5)
	_furn("car_wreck", 24.0, 32.0)
	for k in 6:
		_furn("barrel", float(rng.randi_range(37, 49)) + 0.5, float(rng.randi_range(2, 61)) + 0.5)
	exit_at = Vector2(43.5, 2.5)
	_keep(Rect2i(41, 1, 5, 3))
	_dead(Rect2i(12, 1, 24, 62), 30, "mix")
	_dead(Rect2i(36, 1, 15, 62), 16, "mix")
	_dead(Rect2i(1, 25, 11, 12), 4, "wander")


## THE AIRPORT: a runway and a taxiway across the north, the apron with two airliners and their fuel trucks, the terminal (three gate lounges with jet bridges, the hall, duty free, first aid,
## security), two hangars with a small plane each, a car park at the way in. In from the west road at the car park, out at the east end of the taxiway.
func _airport() -> void:
	_fill(Rect2i(1, 2, 62, 9), "asphalt")
	_fill(Rect2i(1, 13, 62, 4), "asphalt")
	_fill(Rect2i(8, 11, 4, 2), "asphalt")
	_fill(Rect2i(52, 11, 4, 2), "asphalt")
	_fill(Rect2i(17, 17, 46, 21), "sidewalk")
	_fill(Rect2i(2, 46, 18, 16), "asphalt")
	_entry(Rect2i(0, 54, 20, 4), Vector2(4.5, 55.5))
	_road(Rect2i(20, 54, 40, 3))
	for y in range(2, 11):
		for x in range(1, 63):
			mini[_i(x, y)] = 2
	_prop("runway", Rect2(1, 2, 62, 9))
	_prop("taxi", Rect2(1, 13, 62, 4))
	_prop("apron", Rect2(17, 17, 46, 21))
	_prop("parking", Rect2(2, 46, 18, 8), {"bay": 3.0})
	# the hangars
	for hy in [17, 31]:
		var hg := _bldg("hangar", Rect2i(2, hy, 15, 13), [[Rect2i(3, hy + 1, 13, 7), "hangar bay", "hall"], [Rect2i(3, hy + 9, 6, 3), "parts store", "hall", "parts_store"], [Rect2i(10, hy + 9, 6, 3), "workshop", "hall"]],
			[Rect2i(16, hy + 2, 1, 5), Rect2i(5, hy + 8, 2, 1), Rect2i(12, hy + 8, 2, 1)], 2)
		_shut(Rect2i(5, hy + 4, 8, 1))
		_prop("smallplane", Rect2(4.6, hy + 1.6, 9.0, 5.8))
		_furn("tool_chest", 4.0, float(hy) + 1.5, "s", "tool_chest")
		_furn("workbench", 14.0, float(hy) + 1.5, "s", "workbench")
		_furn("jerrycan", 15.5, float(hy) + 7.5)
		_row("shop_shelf", 4.0, float(hy) + 9.5, 2, 2.0, "s", "shelf")
		_furn("crate", 4.5, float(hy) + 11.5, "n", "crate")
		_furn("workbench", 15.0, float(hy) + 9.5, "s", "workbench")
		_furn("tire_stack", 15.5, float(hy) + 11.5, "s", "tire_stack")
		_furn("toolbox", 10.5, float(hy) + 11.5, "n", "toolbox")
		_dead_rooms(hg, 16.0)
	# the terminal
	var tm := _bldg("terminal", Rect2i(22, 38, 38, 15), [
		[Rect2i(23, 39, 11, 5), "gate lounge", "carpet"], [Rect2i(35, 39, 11, 5), "gate lounge", "carpet"], [Rect2i(47, 39, 12, 5), "gate lounge", "carpet"],
		[Rect2i(23, 45, 24, 7), "departure hall", "hall"], [Rect2i(48, 45, 11, 3), "duty free", "kitchen"],
		[Rect2i(48, 49, 5, 3), "first aid", "bath", "first_aid"], [Rect2i(54, 49, 5, 3), "security office", "hall", "security"]],
		[Rect2i(27, 44, 2, 1), Rect2i(39, 44, 2, 1), Rect2i(52, 44, 2, 1), Rect2i(47, 46, 1, 2), Rect2i(50, 48, 2, 1), Rect2i(56, 48, 2, 1),
		Rect2i(28, 38, 2, 1), Rect2i(40, 38, 2, 1), Rect2i(52, 38, 2, 1), Rect2i(33, 52, 4, 1)], 2)
	for gx in [24.0, 36.0, 48.0]:
		_row("bench", gx + 1.0, 40.5, 4, 2.5, "s")
		_row("bench", gx + 1.0, 42.5, 4, 2.5, "n")
		_furn("desk", gx + 9.0, 39.5, "s", "desk")
		_furn("cooler", gx + 0.5, 43.5, "n", "cooler")
	_row("checkout", 26.0, 47.5, 6, 3.0, "s", "desk", 2)
	_row("bench", 27.0, 50.5, 4, 4.0, "n")
	_furn("suitcase", 31.5, 49.5)
	_furn("cart", 41.5, 50.5)
	_row("shop_shelf", 49.0, 45.5, 4, 2.5, "s", "shelf")
	_furn("cooler", 58.5, 47.5, "n", "cooler")
	_furn("bed_single", 48.5, 50.0, "s")
	_furn("medicine_cabinet", 51.5, 49.5, "s", "medicine_cabinet")
	_furn("medicine_cabinet", 52.5, 51.5, "n", "medicine_cabinet")
	_furn("wardrobe", 55.0, 49.5, "s", "locker")
	_furn("desk", 57.0, 51.5, "n", "desk")
	_dead_rooms(tm, 14.0)
	for gx in [28.0, 40.0, 52.0]:
		_prop("jetbridge", Rect2(gx - 0.2, 35.0, 2.4, 3.0))
	# the airliners and their trucks
	for px in [24.0, 44.0]:
		_shut(Rect2i(int(px) + 1, 25, 15, 2))
		_shut(Rect2i(int(px) + 7, 20, 2, 2))
		_shut(Rect2i(int(px) + 7, 30, 2, 2))
		_prop("plane", Rect2(px, 17.6, 17.0, 16.8), {"c": Color(0.75, 0.2, 0.2) if px < 30.0 else Color(0.2, 0.4, 0.72)})
	_yard("fuel truck", Rect2i(41, 19, 2, 5), "petrol", "fuel_truck")
	_yard("fuel truck", Rect2i(18, 31, 5, 2), "petrol", "fuel_truck", {"h": true})
	_yard("baggage cart", Rect2i(36, 33, 3, 2), "shop", "bagcart")
	_yard("baggage cart", Rect2i(56, 33, 3, 2), "shop", "bagcart")
	for k in 7:
		_furn("car_v", float(4 + k * 3) - 0.0, 49.5 if k % 3 != 1 else 59.5)
	_furn("car_wreck", 30.0, 14.5)
	_row("cone", 20.5, 36.5, 6, 6.0)
	exit_at = Vector2(61.5, 14.5)
	_keep(Rect2i(59, 13, 4, 4))
	_dead(Rect2i(17, 17, 46, 21), 20, "mix")
	_dead(Rect2i(1, 2, 62, 15), 12, "wander")
	_dead(Rect2i(2, 46, 18, 16), 6, "mix")


## THE STADIUM: an oval bowl round (32, 30). From the middle out: the pitch (the crowd of dead), the track, the seats (solid but low: a shot goes over; eight aisles), the concourse (food stalls),
## the outer wall with four gates. Four small buildings in the corners. In from the west on the south road, out at the east end of the north road.
const ST_C := Vector2(32.0, 30.0)
const ST_R := Vector2(27.0, 22.0)
const ST_E := [0.40, 0.47, 0.72, 0.9, 1.0]    # pitch, track, seats, concourse, wall (the outer edge of each, as a share of the radii)


static func _st_e(x: float, y: float) -> float:
	return Vector2((x - ST_C.x) / ST_R.x, (y - ST_C.y) / ST_R.y).length()


func _stadium() -> void:
	_road(Rect2i(0, 56, 64, 4))
	_entry(Rect2i(0, 56, 12, 4), Vector2(4.5, 57.5))
	_road(Rect2i(0, 1, 64, 4))
	var gates := [0.0, PI * 0.5, PI, PI * 1.5]
	for y in range(5, 56):
		for x in range(1, 63):
			var e := _st_e(x + 0.5, y + 0.5)
			var ang := fposmod(atan2((y + 0.5 - ST_C.y) / ST_R.y, (x + 0.5 - ST_C.x) / ST_R.x), TAU)
			var rad := e * (ST_R.x + ST_R.y) * 0.5
			var near_gate := false
			for g in gates:
				if absf(angle_difference(ang, g)) * rad < 2.1:
					near_gate = true
			var aisle := false
			for k in 8:
				if absf(angle_difference(ang, float(k) * PI / 4.0)) * rad < 1.1:
					aisle = true
			if e < ST_E[0]:
				_put(x, y, T_GRASS, GR.lawn)
				mini[_i(x, y)] = 3
			elif e < ST_E[1]:
				_put(x, y, T_DIRT, GR.dirt)
			elif e < ST_E[2]:
				_put(x, y, T_CONCRETE, GR.sidewalk, 0 if aisle else 1)
				if not aisle:
					low[_i(x, y)] = 1
					mini[_i(x, y)] = 4
			elif e < ST_E[3]:
				_put(x, y, T_CONCRETE, GR.sidewalk)
			elif e < ST_E[4]:
				_put(x, y, T_CONCRETE, GR.sidewalk, 0 if near_gate else 1)
			elif e < 1.12:
				_put(x, y, T_CONCRETE, GR.sidewalk)
	_prop("bowl", Rect2(ST_C - ST_R, ST_R * 2.0))
	var n := 0
	for k in 16:
		var a := float(k) * PI / 8.0 + PI / 16.0
		var p := ST_C + Vector2(cos(a) * ST_R.x, sin(a) * ST_R.y) * 0.81
		var r := Rect2i(int(round(p.x - 1.0)), int(round(p.y - 1.0)), 2, 2)
		n += 1
		_yard("food stall", r, "shop", "stall", {"c": [Color(0.8, 0.2, 0.2), Color(0.95, 0.75, 0.2), Color(0.2, 0.5, 0.8)][k % 3]})
	groups.append({"name": String(bcfg.get("stalls", {}).get("name", "Food stalls")), "hint": String(bcfg.get("stalls", {}).get("hint", "")), "type": "shop", "rect": Rect2(ST_C - ST_R * 0.9, ST_R * 1.8), "ring": true})
	var a1 := _bldg("security", Rect2i(1, 6, 8, 7), [[Rect2i(2, 7, 6, 5), "security office", "hall"]], [Rect2i(8, 9, 1, 2)], 3)
	_furn("wardrobe", 3.0, 7.5, "s", "locker")
	_furn("desk", 6.0, 7.5, "s", "desk")
	_furn("crate", 2.5, 11.5, "n", "crate")
	var a2 := _bldg("first_aid", Rect2i(55, 6, 8, 7), [[Rect2i(56, 7, 6, 5), "first aid post", "bath"]], [Rect2i(55, 9, 1, 2)], 2)
	_furn("bed_single", 60.5, 9.0, "s")
	_furn("medicine_cabinet", 57.5, 7.5, "s", "medicine_cabinet")
	_furn("medicine_cabinet", 59.5, 11.5, "n", "medicine_cabinet")
	var a3 := _bldg("club_shop", Rect2i(1, 45, 8, 9), [[Rect2i(2, 46, 6, 7), "club shop", "kitchen"]], [Rect2i(8, 48, 1, 2)], 3)
	_row("shop_shelf", 3.0, 46.5, 2, 3.0, "s", "shelf")
	_furn("cooler", 2.5, 51.5, "n", "cooler")
	_furn("checkout", 6.0, 51.5, "n")
	var a4 := _bldg("grounds_store", Rect2i(55, 45, 8, 9), [[Rect2i(56, 46, 6, 7), "grounds store", "hall"]], [Rect2i(55, 48, 1, 2)], 1)
	_furn("workbench", 58.0, 46.5, "s", "workbench")
	_furn("tool_chest", 60.0, 51.5, "n", "tool_chest")
	_furn("toolbox", 56.5, 51.5, "n", "toolbox")
	for h in [a1, a2, a3, a4]:
		_dead_rooms(h, 12.0)
	for k in 5:
		_furn("car_h", float(14 + k * 8), 2.5 if k % 2 == 0 else 58.5)
	exit_at = Vector2(59.5, 2.5)
	_keep(Rect2i(57, 1, 6, 4))
	var pitch := Rect2i(int(ST_C.x - ST_R.x * 0.4), int(ST_C.y - ST_R.y * 0.4), int(ST_R.x * 0.8), int(ST_R.y * 0.8))
	_dead(pitch, 34, "mix", 0.1, 0.04)
	var conc: Array = []
	for y in range(5, 56):
		for x in range(1, 63):
			var e2 := _st_e(x + 0.5, y + 0.5)
			if e2 >= ST_E[2] and e2 < ST_E[3] and solid[_i(x, y)] == 0:
				conc.append(Vector2i(x, y))
	for k in 12:
		var q: Vector2i = conc[rng.randi() % conc.size()]
		_dead(Rect2i(q, Vector2i.ONE), 1, "wander")
	_dead(Rect2i(1, 5, 62, 51), 8, "wander")


## THE HOSPITAL: one big building of wards round two corridors that cross, the pharmacy and the staff room, the theatre, the morgue (its dead lie in rows), the lobby with the main doors and
## the ambulance bay; an ambulance garage, a boiler house and a kiosk beside it. In from the west road at the car park, out at the north-east corner.
func _hospital() -> void:
	_fill(Rect2i(14, 45, 44, 15), "asphalt")
	_entry(Rect2i(0, 51, 14, 4), Vector2(4.5, 52.5))
	_fill(Rect2i(13, 7, 42, 38), "sidewalk")
	_prop("parking", Rect2(16, 52, 40, 7), {"bay": 3.0})
	var hp := _bldg("hospital", Rect2i(14, 8, 40, 36), [
		[Rect2i(15, 24, 38, 3), "corridor", "hall"], [Rect2i(32, 9, 3, 14), "corridor", "hall"], [Rect2i(32, 28, 3, 15), "corridor", "hall"],
		[Rect2i(15, 9, 8, 14), "ward", "bath"], [Rect2i(24, 9, 7, 14), "ward", "bath"], [Rect2i(36, 9, 8, 14), "ward", "bath"],
		[Rect2i(45, 9, 8, 6), "pharmacy", "kitchen"], [Rect2i(45, 16, 8, 7), "staff room", "wood", "staff_room"],
		[Rect2i(15, 28, 8, 15), "morgue", "hall", "morgue"], [Rect2i(24, 28, 7, 15), "operating theatre", "bath"], [Rect2i(36, 28, 8, 15), "ward", "bath"],
		[Rect2i(45, 28, 8, 15), "lobby", "hall"]],
		[Rect2i(18, 23, 2, 1), Rect2i(26, 23, 2, 1), Rect2i(39, 23, 2, 1), Rect2i(48, 23, 2, 1), Rect2i(48, 15, 2, 1),
		Rect2i(18, 27, 2, 1), Rect2i(26, 27, 2, 1), Rect2i(39, 27, 2, 1), Rect2i(48, 27, 2, 1), Rect2i(32, 23, 3, 1), Rect2i(32, 27, 3, 1),
		Rect2i(14, 24, 1, 3), Rect2i(32, 8, 3, 1), Rect2i(47, 43, 4, 1), Rect2i(53, 34, 1, 3), Rect2i(18, 43, 2, 1)], 2)
	for wx in [15, 24, 36]:    # the wards: beds along both long walls, a cabinet by every other
		for wy in [9, 36 - 8]:
			if wy == 28 and wx != 36:
				continue
			var top: int = wy
			var bottom: int = wy + (13 if wy == 9 else 14)
			for k in 3:
				var bx := float(wx) + 0.5 + float(k) * 2.5
				_furn("bed_single", bx, float(top) + 1.0, "s")
				_furn("bed_single", bx, float(bottom), "n")
			_furn("medicine_cabinet", float(wx) + 1.5, float(top) + 4.5, "s", "medicine_cabinet")
			_furn("nightstand", float(wx) + 6.5, float(top) + 0.5, "s", "nightstand")
			_furn("medicine_cabinet", float(wx) + 5.5, float(bottom) - 2.5, "n", "medicine_cabinet")
	_row("shelf_tins", 46.0, 9.5, 3, 2.5, "s", "medicine_cabinet")
	_furn("medicine_cabinet", 46.5, 12.5, "s", "medicine_cabinet")
	_furn("desk", 50.0, 13.5, "n", "desk")
	_furn("dining_table", 48.0, 19.0, "s")
	_furn("fridge", 52.5, 16.5, "s", "fridge")
	_furn("kitchen_counter", 51.5, 16.5, "s", "kitchen_counter")
	_furn("sofa", 48.5, 21.5, "n")
	for k in 3:    # the morgue: rows of trolleys with the dead under sheets
		_furn("bed_single", 16.5 + float(k) * 2.5, 30.0, "s")
		_furn("bed_single", 16.5 + float(k) * 2.5, 35.0, "s")
		_furn("body", 17.0 + float(k) * 2.5, 39.5)
	_furn("wardrobe", 21.0, 41.5, "n", "locker")
	_furn("bed_single", 27.5, 34.0, "s")
	_furn("medicine_cabinet", 25.5, 28.5, "s", "medicine_cabinet")
	_furn("tool_chest", 29.0, 41.5, "n", "tool_chest")
	_furn("desk", 48.0, 31.5, "s", "desk")
	_row("bench", 46.0, 37.5, 3, 2.5, "s")
	_furn("cooler", 52.5, 29.5, "s", "cooler")
	_furn("plant_floor", 45.5, 41.5)
	for k in 3:
		_furn("bed_single", 15.5 + float(k) * 8.0, 25.0, "s")
	_dead_rooms(hp, 15.0)
	_dead(Rect2i(15, 28, 8, 15), 4, "still")    # (the morgue is fuller)
	for r in [Rect2i(38, 46, 5, 2), Rect2i(52, 46, 5, 2), Rect2i(38, 49, 5, 2)]:
		_yard("ambulance", r, "pharmacy", "ambulance")
	groups.append({"name": String(bcfg.get("ambulances", {}).get("name", "Ambulances")), "hint": String(bcfg.get("ambulances", {}).get("hint", "")), "type": "pharmacy", "rect": Rect2(38, 46, 19, 5)})
	var gar := _bldg("garage", Rect2i(56, 26, 7, 12), [[Rect2i(57, 27, 5, 10), "garage", "hall"]], [Rect2i(56, 30, 1, 3)], 1)
	_furn("workbench", 59.0, 27.5, "s", "workbench")
	_furn("tool_chest", 59.0, 35.5, "n", "tool_chest")
	_furn("jerrycan", 61.5, 31.5)
	_furn("tire_stack", 61.5, 33.5, "s", "tire_stack")
	var boil := _bldg("boiler", Rect2i(56, 8, 7, 8), [[Rect2i(57, 9, 5, 6), "boiler room", "hall"]], [Rect2i(56, 11, 1, 2)], 1)
	_furn("workbench", 59.0, 9.5, "s", "workbench")
	_furn("crate", 60.5, 13.5, "n", "crate")
	var ki := _bldg("kiosk", Rect2i(2, 38, 8, 6), [[Rect2i(3, 39, 6, 4), "kiosk", "kitchen"]], [Rect2i(9, 40, 1, 2)], 4)
	_furn("shop_shelf", 4.0, 39.5, "s", "shelf")
	_furn("cooler", 7.5, 39.5, "s", "cooler")
	_furn("checkout", 5.0, 42.5, "n")
	for h in [gar, boil, ki]:
		_dead_rooms(h, 12.0)
	for k in 6:
		_furn("car_v" if k % 2 == 0 else "car_h", float(17 + k * 6) + 0.5, 55.5)
	exit_at = Vector2(60.5, 3.5)
	_keep(Rect2i(58, 1, 5, 5))
	_dead(Rect2i(1, 1, 62, 62), 14, "wander")
	_dead(Rect2i(14, 45, 44, 15), 8, "mix")


## THE SUPERMARKET: the big store (the sales floor with four aisles of shelves and a cross aisle, the checkouts, the stockroom, a pharmacy counter, the office), the car park with its bays,
## trolleys and cars, a petrol station, a bakery and a hardware shop on the west side. In from the west road at the car park, out at the loading dock behind the store.
func _supermarket() -> void:
	_fill(Rect2i(10, 34, 52, 27), "asphalt")
	_entry(Rect2i(0, 44, 10, 4), Vector2(4.5, 45.5))
	_road(Rect2i(17, 1, 46, 3))
	_fill(Rect2i(17, 4, 42, 30), "sidewalk")
	_prop("parking", Rect2(12, 36, 48, 8), {"bay": 3.0})
	_prop("parking", Rect2(12, 50, 48, 8), {"bay": 3.0})
	var st := _bldg("store", Rect2i(18, 5, 40, 27), [
		[Rect2i(19, 6, 20, 6), "stockroom", "hall", "stockroom"], [Rect2i(40, 6, 8, 6), "pharmacy", "kitchen", "pharmacy"], [Rect2i(49, 6, 8, 6), "office", "wood"],
		[Rect2i(19, 13, 38, 18), "shop floor", "kitchen"]],
		[Rect2i(28, 12, 3, 1), Rect2i(43, 12, 2, 1), Rect2i(52, 12, 2, 1), Rect2i(24, 5, 4, 1), Rect2i(34, 31, 6, 1)], 4)
	for ay in [15.5, 18.5, 21.5, 24.5]:
		for k in 7:
			_furn("shop_shelf", 22.0 + float(k) * 2.0, ay, "s", "shelf" if k % 2 == 0 else "")
			_furn("shop_shelf", 41.0 + float(k) * 2.0, ay, "s", "shelf" if k % 2 == 1 else "")
	for k in 6:
		_furn("cooler", 55.5, 14.5 + float(k) * 2.0, "w", "cooler")
	_row("checkout", 22.0, 28.5, 4, 3.0, "s")
	_row("checkout", 44.0, 28.5, 4, 3.0, "s")
	_row("crate", 20.5, 6.5, 8, 1.0, "s", "crate", 2)
	_row("shop_shelf", 31.0, 6.5, 4, 2.0, "s", "shelf")
	_furn("pallet", 22.0, 10.5)
	_row("shelf_tins", 41.0, 6.5, 3, 2.5, "s", "medicine_cabinet")
	_furn("medicine_cabinet", 46.5, 10.5, "n", "medicine_cabinet")
	_furn("desk", 52.0, 7.5, "s", "desk")
	_furn("wardrobe", 55.0, 6.5, "s", "locker")
	_dead_rooms(st, 22.0)
	_dead(Rect2i(19, 14, 38, 12), 8, "mix")    # the crowd between the aisles
	var bk := _bldg("bakery", Rect2i(3, 6, 12, 9), [[Rect2i(4, 7, 10, 7), "bakery", "kitchen"]], [Rect2i(14, 9, 1, 2)], 4)
	_row("kitchen_counter", 4.5, 7.5, 4, 1.0, "s", "kitchen_counter", 2)
	_furn("display_case", 10.0, 11.5, "n", "shelf")
	_furn("fridge", 12.5, 7.5, "s", "fridge")
	var hw := _bldg("hardware", Rect2i(3, 18, 12, 9), [[Rect2i(4, 19, 10, 7), "hardware shop", "hall"]], [Rect2i(14, 21, 1, 2)], 1)
	_row("shop_shelf", 5.0, 19.5, 4, 2.5, "s", "shelf", 2)
	_furn("tool_chest", 6.0, 24.5, "n", "tool_chest")
	_furn("workbench", 11.0, 24.5, "n", "workbench")
	var pk := _bldg("petrol", Rect2i(2, 54, 8, 6), [[Rect2i(3, 55, 6, 4), "petrol kiosk", "kitchen"]], [Rect2i(5, 54, 2, 1)], 2)
	_furn("shop_shelf", 4.0, 57.5, "n", "shelf")
	_furn("cooler", 7.5, 57.5, "n", "cooler")
	_furn("gas_pump", 4.5, 50.5, "s")
	_furn("gas_pump", 7.5, 50.5, "s")
	_prop("canopy", Rect2(2.5, 48.6, 7.0, 3.8))
	for h in [bk, hw, pk]:
		_dead_rooms(h, 14.0)
	for row_y in [37.5, 51.5]:
		for k in 16:
			if rng.randf() < 0.55:
				_furn("car_v", 13.5 + float(k) * 3.0, row_y + 2.0)
	for k in 7:
		_furn("cart" if k % 3 else "cart_fallen", float(rng.randi_range(12, 58)) + 0.5, float(rng.randi_range(44, 49)) + 0.5)
	exit_at = Vector2(60.5, 2.5)
	_keep(Rect2i(58, 1, 5, 3))
	_dead(Rect2i(10, 34, 52, 27), 14, "mix")
	_dead(Rect2i(17, 1, 46, 4), 4, "wander")


## THE POLICE STATION: the station (the armoury, the evidence store, the locker room along the north; the cell block with four cells, the offices and the front lobby along the south), sandbags and
## barriers at its door where somebody held out, patrol cars in the car park, a motor pool, a clinic, a hardware shop and the fuel pumps. In from the west road, out at the north-east corner.
func _police() -> void:
	_road(Rect2i(0, 40, 50, 4))
	_entry(Rect2i(0, 40, 12, 4), Vector2(4.5, 41.5))
	_fill(Rect2i(50, 6, 12, 34), "asphalt")
	_fill(Rect2i(15, 7, 34, 28), "sidewalk")
	_fill(Rect2i(16, 34, 32, 6), "sidewalk")
	_prop("parking", Rect2(50, 8, 12, 30), {"bay": 3.0, "v": true})
	var ps := _bldg("station", Rect2i(16, 8, 32, 26), [
		[Rect2i(17, 9, 9, 10), "armoury", "hall", "armoury"], [Rect2i(27, 9, 8, 10), "evidence store", "hall", "evidence"], [Rect2i(36, 9, 11, 10), "locker room", "hall"],
		[Rect2i(17, 20, 30, 2), "corridor", "hall"], [Rect2i(17, 23, 14, 2), "cell corridor", "hall"],
		[Rect2i(17, 26, 3, 7), "cell", "hall"], [Rect2i(21, 26, 3, 7), "cell", "hall"], [Rect2i(25, 26, 3, 7), "cell", "hall"], [Rect2i(29, 26, 2, 7), "cell", "hall"],
		[Rect2i(32, 23, 6, 10), "offices", "carpet"], [Rect2i(39, 23, 8, 10), "front desk", "hall"]],
		[Rect2i(20, 19, 2, 1), Rect2i(30, 19, 2, 1), Rect2i(40, 19, 2, 1), Rect2i(23, 22, 2, 1), Rect2i(18, 25, 1, 1), Rect2i(22, 25, 1, 1), Rect2i(26, 25, 1, 1),
		Rect2i(29, 25, 1, 1), Rect2i(34, 22, 2, 1), Rect2i(42, 22, 2, 1), Rect2i(41, 33, 3, 1), Rect2i(16, 20, 1, 2)], 1)
	_prop("bars", Rect2(17, 25, 14, 1))
	_row("wardrobe", 18.0, 9.5, 4, 2.0, "s", "gun locker", 2)
	_furn("crate", 17.5, 15.5, "s", "crate")
	_furn("crate", 18.5, 17.5, "s")
	_furn("tool_chest", 24.0, 17.5, "n")
	_row("shop_shelf", 28.0, 9.5, 3, 2.5, "s")
	_furn("box", 28.5, 16.5, "s", "box")
	_furn("crate", 33.5, 17.5, "n")
	_row("wardrobe", 37.0, 9.5, 5, 2.0, "s", "locker", 2)
	_row("bench", 39.0, 14.5, 3, 3.0, "s")
	for cx in [18.5, 22.5, 26.5, 29.5]:
		_furn("bunk_bed" if cx < 29.0 else "bed_single", cx, 30.0, "s")
		_furn("toilet", cx + (1.0 if cx < 29.0 else 0.0), 32.5, "n")
	_furn("desk", 34.0, 24.5, "s", "desk")
	_furn("desk", 34.0, 28.5, "s", "desk")
	_furn("bookshelf", 34.0, 32.5, "n", "shelf")
	_furn("desk", 43.0, 26.5, "s", "desk")
	_row("bench", 41.0, 31.5, 2, 3.0, "n")
	_furn("medicine_cabinet", 46.5, 23.5, "s", "medicine_cabinet")
	_dead_rooms(ps, 14.0)
	for k in 5:
		_furn("sandbags", 32.5 + float(k) * 3.0, 36.5, "s")
	_furn("barrier_fallen", 29.0, 38.5)
	_row("cone", 20.5, 38.5, 3, 3.0)
	_furn("body", 38.0, 38.0)
	for r in [Rect2i(52, 10, 2, 5), Rect2i(55, 10, 2, 5), Rect2i(58, 24, 2, 5), Rect2i(52, 31, 2, 5)]:
		_yard("patrol car", r, "police" if r.position.x == 52 else "", "patrol")
	groups.append({"name": String(bcfg.get("patrol_cars", {}).get("name", "Patrol cars")), "hint": String(bcfg.get("patrol_cars", {}).get("hint", "")), "type": "police", "rect": Rect2(51, 9, 10, 28)})
	for k in 3:
		_furn("car_v", 55.0 + float(k) * 3.0 - (3.0 if k == 2 else 0.0), 18.5 + float(k) * 6.0)
	var mp := _bldg("motor_pool", Rect2i(50, 46, 12, 9), [[Rect2i(51, 47, 10, 7), "motor pool", "hall"]], [Rect2i(54, 46, 4, 1)], 1)
	_furn("car_h", 55.5, 51.5)
	_furn("workbench", 52.0, 52.5, "n", "workbench")
	_furn("tool_chest", 59.0, 52.5, "n", "tool_chest")
	_furn("jerrycan", 60.5, 48.5)
	var cl := _bldg("clinic", Rect2i(3, 48, 10, 8), [[Rect2i(4, 49, 8, 6), "clinic", "bath"]], [Rect2i(7, 48, 2, 1)], 2)
	_furn("bed_single", 5.5, 52.0, "s")
	_furn("medicine_cabinet", 9.5, 49.5, "s", "medicine_cabinet")
	_furn("medicine_cabinet", 10.5, 53.5, "n", "medicine_cabinet")
	var hw := _bldg("hardware", Rect2i(3, 10, 10, 9), [[Rect2i(4, 11, 8, 7), "hardware shop", "hall"]], [Rect2i(12, 13, 1, 2)], 3)
	_row("shop_shelf", 5.0, 11.5, 3, 2.5, "s", "shelf", 2)
	_furn("tool_chest", 6.0, 16.5, "n", "tool_chest")
	var pp := _bldg("pumps", Rect2i(20, 48, 8, 6), [[Rect2i(21, 49, 6, 4), "fuel kiosk", "kitchen"]], [Rect2i(23, 48, 2, 1)], 2)
	_furn("shop_shelf", 22.0, 52.5, "n", "shelf")
	_furn("jerrycan", 25.5, 50.5)
	_furn("gas_pump", 21.5, 45.5, "s")
	_furn("gas_pump", 25.5, 45.5, "s")
	for h in [mp, cl, hw, pp]:
		_dead_rooms(h, 14.0)
	exit_at = Vector2(60.5, 2.5)
	_keep(Rect2i(58, 1, 5, 4))
	_dead(Rect2i(16, 34, 32, 6), 8, "still", 0.15)
	_dead(Rect2i(50, 6, 12, 34), 8, "mix")
	_dead(Rect2i(1, 1, 62, 62), 10, "wander")


## THE INDUSTRIAL YARD: a chain-link fence round the yard (a gate on the west, one on the east), the workshop, the garage with a car on the ramp, the warehouse, the security hut, machinery
## (an excavator, a generator, a conveyor), scrap piles, fuel tanks, pallets and drums. In from the west road, out past the east gate.
func _industrial() -> void:
	_entry(Rect2i(0, 28, 9, 4), Vector2(4.5, 29.5))
	var yard := Rect2i(8, 4, 48, 54)
	for y in range(yard.position.y + 1, yard.end.y - 1):
		for x in range(yard.position.x + 1, yard.end.x - 1):
			_put(x, y, T_DIRT, GR.gravel)
	_fill(Rect2i(9, 28, 46, 4), "sidewalk")
	_fill(Rect2i(28, 20, 4, 30), "sidewalk")
	_fill(Rect2i(28, 46, 28, 4), "sidewalk")
	_fill(Rect2i(55, 46, 8, 4), "asphalt")
	_fence_rect(yard, [Rect2i(8, 28, 1, 4), Rect2i(55, 46, 1, 4)])
	var wsh := _bldg("workshop", Rect2i(11, 7, 16, 12), [[Rect2i(12, 8, 14, 7), "workshop", "hall"], [Rect2i(12, 16, 6, 2), "tool room", "hall"], [Rect2i(19, 16, 7, 2), "office", "wood"]],
		[Rect2i(26, 9, 1, 4), Rect2i(14, 15, 2, 1), Rect2i(21, 15, 2, 1), Rect2i(22, 18, 2, 1)], 3)
	_row("workbench", 14.0, 8.5, 3, 4.0, "s", "workbench")
	_furn("tool_chest", 24.0, 13.5, "n", "tool_chest")
	_furn("pallet", 15.0, 12.5)
	_row("toolbox", 12.5, 16.5, 3, 2.0, "s", "toolbox")
	_furn("desk", 22.0, 16.5, "s", "desk")
	var gar := _bldg("garage", Rect2i(32, 7, 20, 11), [[Rect2i(33, 8, 18, 9), "garage", "hall"]], [Rect2i(36, 17, 4, 1), Rect2i(45, 17, 4, 1)], 1)
	_furn("car_h", 38.5, 11.0)
	_furn("car_wreck", 46.0, 11.0)
	_row("tire_stack", 33.5, 8.5, 3, 1.0, "s", "tire_stack", 2)
	_furn("tool_chest", 50.0, 8.5, "s", "tool_chest")
	_furn("workbench", 42.0, 8.5, "s", "workbench")
	_row("jerrycan", 34.5, 15.5, 3, 1.0, "s", "jerrycan")
	_furn("crate", 50.5, 15.5, "n", "crate")
	var wh := _bldg("warehouse", Rect2i(11, 38, 18, 16), [[Rect2i(12, 39, 16, 10), "warehouse floor", "hall"], [Rect2i(12, 50, 7, 3), "office", "wood"], [Rect2i(20, 50, 8, 3), "washroom", "bath"]],
		[Rect2i(18, 38, 4, 1), Rect2i(14, 49, 2, 1), Rect2i(23, 49, 2, 1)], 3)
	_row("shop_shelf", 13.0, 41.5, 3, 4.0, "s", "shelf", 2)
	_row("shop_shelf", 13.0, 45.5, 3, 4.0, "s", "shelf", 2)
	_row("crate", 25.5, 40.5, 3, 1.0, "s", "crate", 2)
	_furn("pallet", 25.0, 46.5)
	_furn("desk", 15.0, 50.5, "s", "desk")
	_furn("toilet", 26.5, 50.5, "s")
	var sec := _bldg("security", Rect2i(36, 40, 10, 6), [[Rect2i(37, 41, 8, 4), "security hut", "hall"]], [Rect2i(36, 42, 1, 2)], 2)
	_furn("wardrobe", 41.0, 41.5, "s", "locker")
	_furn("desk", 43.0, 44.5, "n", "desk")
	for h in [wsh, gar, wh, sec]:
		_dead_rooms(h, 13.0)
	# machinery and scrap
	_shut(Rect2i(34, 22, 5, 4))
	_prop("excavator", Rect2(34, 22, 5, 4))
	_shut(Rect2i(41, 34, 3, 2))
	_prop("generator", Rect2(41, 34, 3, 2))
	_shut(Rect2i(14, 33, 10, 1))
	_prop("conveyor", Rect2(13.6, 32.7, 10.8, 1.6))
	for r in [Rect2i(13, 22, 4, 3), Rect2i(20, 23, 3, 3), Rect2i(46, 21, 4, 3), Rect2i(35, 51, 4, 3), Rect2i(49, 37, 3, 3)]:
		_yard("scrap pile", r, "hardware", "scrap")
	groups.append({"name": String(bcfg.get("scrap", {}).get("name", "Scrap piles")), "hint": String(bcfg.get("scrap", {}).get("hint", "")), "type": "hardware", "rect": Rect2(13, 21, 39, 33)})
	for r in [Rect2i(46, 27, 3, 3), Rect2i(50, 27, 3, 3)]:
		_yard("fuel tank", r, "petrol", "tank")
	_furn("gas_pump", 47.5, 31.5, "s")
	for k in 8:
		_furn("barrel", float(rng.randi_range(38, 53)) + 0.5, float(rng.randi_range(36, 44)) + 0.5)
	for k in 4:
		_furn("pallet", float(rng.randi_range(12, 24)) + 0.5, float(rng.randi_range(26, 36)) + 0.5)
	exit_at = Vector2(60.5, 47.5)
	_keep(Rect2i(57, 45, 6, 6))
	_dead(yard.grow(-1), 30, "mix", 0.08, 0.06)
	_dead(Rect2i(1, 1, 62, 62), 6, "wander")


# ================================================================== THE PAINTER ==

const INK := Color(0.11, 0.09, 0.08)


## The code-drawn things of a site (world px). `high`: only the things over the people (the crane booms); else the ground layer, under the people and the roofs.
static func paint(c: CanvasItem, town: Dictionary, high: bool) -> void:
	var s: Dictionary = town.get("site", {})
	for p in s.get("props", []):
		var r: Rect2 = Rect2(Rect2(p.r).position * TILE, Rect2(p.r).size * TILE)
		var k := String(p.k)
		if high:
			if k == "crane":
				_crane_boom(c, r)
			continue
		match k:
			"water":
				_water(c, r)
			"quay":
				c.draw_rect(r, Color(0.62, 0.6, 0.55))
				c.draw_rect(r, INK, false, 3.0)
				for y in range(0, int(r.size.y), int(TILE * 4.0)):
					c.draw_circle(r.position + Vector2(r.size.x * 0.5, float(y) + TILE), 9.0, INK)
					c.draw_circle(r.position + Vector2(r.size.x * 0.5, float(y) + TILE), 6.0, Color(0.3, 0.3, 0.32))
				c.draw_line(r.position + Vector2(-TILE * 0.5, 0), r.position + Vector2(-TILE * 0.5, r.size.y), Color(0.95, 0.8, 0.2, 0.8), 5.0)
			"hull":
				_hull(c, r)
			"crane":
				_crane_base(c, r)
			"stack":
				_stack(c, r, p)
			"tank":
				_tank(c, r)
			"fuel_truck":
				_truck(c, r, Color(0.85, 0.85, 0.82), Color(0.8, 0.2, 0.15), "FUEL", p.get("h", false))
			"ambulance":
				_ambulance(c, r)
			"patrol":
				_patrol(c, r)
			"runway":
				_runway(c, r)
			"taxi":
				var my := r.position.y + r.size.y * 0.5
				c.draw_line(Vector2(r.position.x, my), Vector2(r.end.x, my), Color(0.95, 0.78, 0.15), 5.0)
				for cx in [10.0, 54.0]:
					c.draw_line(Vector2(cx * TILE, my), Vector2(cx * TILE, 6.0 * TILE), Color(0.95, 0.78, 0.15), 5.0)
			"apron":
				for k2 in 6:
					var x := r.position.x + (2.0 + float(k2) * 7.5) * TILE
					c.draw_line(Vector2(x, r.position.y + TILE), Vector2(x, r.end.y - TILE * 2.0), Color(0.95, 0.78, 0.15, 0.7), 4.0)
				c.draw_rect(r.grow(-6.0), Color(0.95, 0.78, 0.15, 0.5), false, 3.0)
			"plane":
				_plane(c, r, p.get("c", Color(0.75, 0.2, 0.2)), false)
			"smallplane":
				_plane(c, r, Color(0.2, 0.5, 0.35), true)
			"jetbridge":
				c.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.25))
				c.draw_rect(r, Color(0.7, 0.72, 0.74))
				for y in range(0, int(r.size.y), 22):
					c.draw_line(r.position + Vector2(0, float(y)), r.position + Vector2(r.size.x, float(y)), Color(0.5, 0.52, 0.55), 2.0)
				c.draw_rect(r, INK, false, 3.0)
			"bagcart":
				c.draw_rect(r.grow(-6.0), Color(0.45, 0.45, 0.5))
				for k3 in 3:
					c.draw_rect(Rect2(r.position + Vector2(10.0 + k3 * 58.0, 12.0), Vector2(48, r.size.y - 24.0)), Color(0.75, 0.55, 0.3))
					c.draw_rect(Rect2(r.position + Vector2(10.0 + k3 * 58.0, 12.0), Vector2(48, r.size.y - 24.0)), INK, false, 2.0)
				c.draw_rect(r.grow(-6.0), INK, false, 3.0)
			"parking":
				var bay := float(p.get("bay", 3.0)) * TILE
				if bool(p.get("v", false)):
					var y2 := r.position.y
					while y2 <= r.end.y:
						c.draw_line(Vector2(r.position.x, y2), Vector2(r.position.x + TILE * 2.0, y2), Color(0.92, 0.92, 0.88, 0.6), 4.0)
						c.draw_line(Vector2(r.end.x - TILE * 2.0, y2), Vector2(r.end.x, y2), Color(0.92, 0.92, 0.88, 0.6), 4.0)
						y2 += bay
				else:
					var x2 := r.position.x
					while x2 <= r.end.x:
						c.draw_line(Vector2(x2, r.position.y), Vector2(x2, r.position.y + TILE * 2.6), Color(0.92, 0.92, 0.88, 0.6), 4.0)
						c.draw_line(Vector2(x2, r.end.y - TILE * 2.6), Vector2(x2, r.end.y), Color(0.92, 0.92, 0.88, 0.6), 4.0)
						x2 += bay
			"canopy":
				c.draw_rect(r, Color(0.9, 0.9, 0.88, 0.35))
				c.draw_rect(r, Color(0.8, 0.2, 0.15, 0.9), false, 6.0)
			"bowl":
				_bowl(c, r)
			"stall":
				_stall(c, r, p.get("c", Color(0.8, 0.2, 0.2)))
			"bars":
				for x in range(int(r.position.x), int(r.end.x), 12):
					c.draw_line(Vector2(float(x), r.position.y + 6.0), Vector2(float(x), r.end.y - 6.0), Color(0.25, 0.27, 0.3), 4.0)
			"excavator":
				_excavator(c, r)
			"generator":
				_box(c, r, Color(0.3, 0.5, 0.32), true)
			"conveyor":
				_box(c, r, Color(0.4, 0.4, 0.42), false)
				for x in range(int(r.position.x) + 10, int(r.end.x), 24):
					c.draw_line(Vector2(float(x), r.position.y + 6.0), Vector2(float(x), r.end.y - 6.0), Color(0.2, 0.2, 0.22), 3.0)
			"scrap":
				_scrap(c, r)


static func _shadow(c: CanvasItem, r: Rect2, off: float = 10.0) -> void:
	c.draw_rect(Rect2(r.position + Vector2(off, off * 1.3), r.size), Color(0, 0, 0, 0.28))


static func _box(c: CanvasItem, r: Rect2, col: Color, vents: bool) -> void:
	_shadow(c, r)
	c.draw_rect(r, col)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.3)), col.lightened(0.15))
	if vents:
		for k in 4:
			c.draw_line(r.position + Vector2(r.size.x * (0.2 + k * 0.18), r.size.y * 0.45), r.position + Vector2(r.size.x * (0.2 + k * 0.18), r.size.y * 0.85), col.darkened(0.4), 3.0)
	c.draw_rect(r, INK, false, 3.5)


static func _water(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r, Color(0.16, 0.33, 0.48))
	for k in 70:
		var x := r.position.x + fposmod(float(k) * 173.7, r.size.x)
		var y := r.position.y + fposmod(float(k) * 291.3, r.size.y)
		c.draw_line(Vector2(x, y), Vector2(x + 46.0, y), Color(0.45, 0.62, 0.75, 0.45), 3.0)
		c.draw_line(Vector2(x + 14.0, y + 9.0), Vector2(x + 36.0, y + 9.0), Color(0.45, 0.62, 0.75, 0.3), 2.0)


static func _hull(c: CanvasItem, r: Rect2) -> void:
	var cx := r.position.x + r.size.x * 0.5
	var pts := PackedVector2Array([Vector2(cx, r.position.y), Vector2(r.end.x, r.position.y + r.size.x * 1.2), Vector2(r.end.x, r.end.y - 20.0), Vector2(r.end.x - 20.0, r.end.y),
		Vector2(r.position.x + 20.0, r.end.y), Vector2(r.position.x, r.end.y - 20.0), Vector2(r.position.x, r.position.y + r.size.x * 1.2)])
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(14, 18))
	c.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
	c.draw_colored_polygon(pts, Color(0.55, 0.16, 0.14))
	var deck := PackedVector2Array()
	for q in pts:
		deck.append(Vector2(cx, r.position.y + r.size.y * 0.5) + (q - Vector2(cx, r.position.y + r.size.y * 0.5)) * Vector2(0.84, 0.96))
	c.draw_colored_polygon(deck, Color(0.42, 0.44, 0.46))
	var pl := pts.duplicate()
	pl.append(pts[0])
	c.draw_polyline(pl, INK, 5.0)
	var cols := [Color(0.72, 0.24, 0.2), Color(0.2, 0.42, 0.66), Color(0.3, 0.55, 0.32), Color(0.85, 0.55, 0.18)]
	var y := r.position.y + r.size.x * 1.6
	var k := 0
	while y < r.end.y - TILE * 9.0:
		var row := Rect2(r.position.x + TILE * 1.1, y, r.size.x - TILE * 2.2, TILE * 1.6)
		c.draw_rect(row, cols[k % cols.size()])
		c.draw_rect(row, INK, false, 2.5)
		y += TILE * 1.9
		k += 1
	var bridge := Rect2(r.position.x + TILE * 1.2, r.end.y - TILE * 7.0, r.size.x - TILE * 2.4, TILE * 4.0)
	c.draw_rect(Rect2(bridge.position + Vector2(10, 14), bridge.size), Color(0, 0, 0, 0.3))
	c.draw_rect(bridge, Color(0.92, 0.92, 0.88))
	for wx in range(int(bridge.position.x) + 16, int(bridge.end.x) - 16, 30):
		c.draw_rect(Rect2(float(wx), bridge.position.y + 16.0, 16.0, 12.0), Color(0.2, 0.3, 0.4))
	c.draw_rect(bridge, INK, false, 3.5)
	c.draw_circle(Vector2(cx, r.end.y - TILE * 1.6), TILE * 0.6, Color(0.2, 0.2, 0.22))
	c.draw_arc(Vector2(cx, r.end.y - TILE * 1.6), TILE * 0.6, 0, TAU, 20, INK, 3.0)


const CRANE := Color(0.93, 0.6, 0.12)


static func _crane_base(c: CanvasItem, r: Rect2) -> void:
	c.draw_line(Vector2(r.position.x + 30.0, -TILE), Vector2(r.position.x + 30.0, 64.0 * TILE), Color(0.35, 0.33, 0.3, 0.6), 4.0)
	c.draw_line(Vector2(r.end.x - 30.0, -TILE), Vector2(r.end.x - 30.0, 64.0 * TILE), Color(0.35, 0.33, 0.3, 0.6), 4.0)
	for q in [r.position, Vector2(r.end.x - TILE, r.position.y), Vector2(r.position.x, r.end.y - TILE), Vector2(r.end.x - TILE, r.end.y - TILE)]:
		var leg := Rect2(q + Vector2(6, 6), Vector2(TILE - 12.0, TILE - 12.0))
		c.draw_rect(Rect2(leg.position + Vector2(8, 10), leg.size), Color(0, 0, 0, 0.3))
		c.draw_rect(leg, CRANE)
		c.draw_rect(leg, INK, false, 3.0)
	for y in [r.position.y + TILE * 0.5, r.end.y - TILE * 0.5]:
		c.draw_line(Vector2(r.position.x + TILE * 0.5, y), Vector2(r.end.x - TILE * 0.5, y), INK, 14.0)
		c.draw_line(Vector2(r.position.x + TILE * 0.5, y), Vector2(r.end.x - TILE * 0.5, y), CRANE, 9.0)


static func _crane_boom(c: CanvasItem, r: Rect2) -> void:
	var y := r.position.y + r.size.y * 0.5
	var a := Vector2(r.position.x - TILE * 3.0, y)
	var b := Vector2(r.end.x + TILE * 13.0, y)
	c.draw_rect(Rect2(a + Vector2(30, 60) - Vector2(0, 16), Vector2(b.x - a.x, 32)), Color(0, 0, 0, 0.18))
	for off in [-16.0, 16.0]:
		c.draw_line(a + Vector2(0, off), b + Vector2(0, off), INK, 9.0)
		c.draw_line(a + Vector2(0, off), b + Vector2(0, off), CRANE, 5.0)
	var x := a.x
	var up := true
	while x < b.x - 30.0:
		c.draw_line(Vector2(x, y + (-16.0 if up else 16.0)), Vector2(x + 32.0, y + (16.0 if up else -16.0)), CRANE.darkened(0.25), 3.0)
		x += 32.0
		up = not up
	var cab := Rect2(Vector2(r.position.x + r.size.x * 0.55, y - 26.0), Vector2(70, 52))
	c.draw_rect(cab, Color(0.95, 0.92, 0.85))
	c.draw_rect(Rect2(cab.position + Vector2(8, 10), Vector2(30, 18)), Color(0.25, 0.4, 0.55))
	c.draw_rect(cab, INK, false, 3.0)
	c.draw_rect(Rect2(a - Vector2(0, 30), Vector2(TILE * 2.0, 60)), Color(0.45, 0.45, 0.47))
	c.draw_rect(Rect2(a - Vector2(0, 30), Vector2(TILE * 2.0, 60)), INK, false, 3.0)


static func _stack(c: CanvasItem, r: Rect2, p: Dictionary) -> void:
	var col: Color = p.get("c", Color(0.7, 0.3, 0.2))
	var rr := r.grow(-3.0)
	_shadow(c, rr, 12.0 if bool(p.get("tall", false)) else 7.0)
	c.draw_rect(rr, col.darkened(0.12) if bool(p.get("tall", false)) else col)
	var ribs := int(rr.size.x / 14.0)
	for k in ribs:
		var x := rr.position.x + 7.0 + float(k) * 14.0
		c.draw_line(Vector2(x, rr.position.y + 4.0), Vector2(x, rr.end.y - 4.0), col.darkened(0.3), 2.0)
	if bool(p.get("tall", false)):
		var top := Rect2(rr.position + Vector2(6, -6), rr.size - Vector2(10, 8))
		c.draw_rect(top, col.lightened(0.08))
		for k in ribs - 1:
			var x2 := top.position.x + 7.0 + float(k) * 14.0
			c.draw_line(Vector2(x2, top.position.y + 4.0), Vector2(x2, top.end.y - 4.0), col.darkened(0.25), 2.0)
		c.draw_rect(top, INK, false, 2.5)
	c.draw_rect(rr, INK, false, 3.5)
	if bool(p.get("open", false)):    # the open one: its doors stand open at the west end
		c.draw_rect(Rect2(rr.position + Vector2(2, 4), Vector2(18, rr.size.y - 8.0)), Color(0.12, 0.1, 0.09))
		c.draw_line(rr.position + Vector2(0, 2), rr.position + Vector2(-26, -10), col.darkened(0.2), 6.0)
		c.draw_line(Vector2(rr.position.x, rr.end.y - 2.0), Vector2(rr.position.x - 26.0, rr.end.y + 10.0), col.darkened(0.2), 6.0)


static func _tank(c: CanvasItem, r: Rect2) -> void:
	var cc := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.46
	c.draw_circle(cc + Vector2(12, 16), rad, Color(0, 0, 0, 0.3))
	c.draw_circle(cc, rad, Color(0.82, 0.83, 0.8))
	c.draw_circle(cc, rad * 0.62, Color(0.74, 0.75, 0.72))
	c.draw_arc(cc, rad, 0, TAU, 32, INK, 4.0)
	c.draw_arc(cc, rad * 0.62, 0, TAU, 24, Color(0.5, 0.5, 0.48), 2.0)
	c.draw_line(cc + Vector2(rad * 0.62, 0), cc + Vector2(rad, 0), INK, 3.0)
	c.draw_string(ThemeDB.fallback_font, cc + Vector2(-rad, 8), "FUEL", HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, 22, Color(0.75, 0.15, 0.12))


## A truck from the north (a cab at the top) or the west (`h`): the cab, the tank or the box, the word.
static func _truck(c: CanvasItem, r: Rect2, body: Color, stripe: Color, word: String, h: bool) -> void:
	var rr := r.grow(-4.0)
	_shadow(c, rr)
	var cab := Rect2(rr.position, Vector2(rr.size.x, rr.size.y * 0.24)) if not h else Rect2(rr.position, Vector2(rr.size.x * 0.24, rr.size.y))
	var box := Rect2(rr.position + Vector2(0, rr.size.y * 0.28), Vector2(rr.size.x, rr.size.y * 0.72)) if not h else Rect2(rr.position + Vector2(rr.size.x * 0.28, 0), Vector2(rr.size.x * 0.72, rr.size.y))
	c.draw_rect(cab, stripe)
	c.draw_rect(cab.grow(-10.0), Color(0.25, 0.35, 0.45))
	c.draw_rect(cab, INK, false, 3.0)
	c.draw_rect(box, body)
	c.draw_rect(box.grow(-10.0), body.lightened(0.12))
	if not h:
		c.draw_line(Vector2(box.position.x + 6.0, box.get_center().y), Vector2(box.end.x - 6.0, box.get_center().y), stripe, 8.0)
	else:
		c.draw_line(Vector2(box.get_center().x, box.position.y + 6.0), Vector2(box.get_center().x, box.end.y - 6.0), stripe, 8.0)
	c.draw_rect(box, INK, false, 3.5)
	c.draw_string(ThemeDB.fallback_font, box.get_center() + Vector2(-50, 7), word, HORIZONTAL_ALIGNMENT_CENTER, 100, 18, stripe.darkened(0.2))


static func _ambulance(c: CanvasItem, r: Rect2) -> void:
	var rr := r.grow(-4.0)
	_shadow(c, rr)
	c.draw_rect(rr, Color(0.95, 0.95, 0.92))
	c.draw_rect(Rect2(rr.position + Vector2(0, rr.size.y * 0.42), Vector2(rr.size.x, rr.size.y * 0.16)), Color(0.85, 0.15, 0.12))
	c.draw_rect(Rect2(Vector2(rr.end.x - rr.size.x * 0.22, rr.position.y + 8.0), Vector2(rr.size.x * 0.16, rr.size.y - 16.0)), Color(0.25, 0.35, 0.45))
	var cc := rr.position + Vector2(rr.size.x * 0.4, rr.size.y * 0.5)
	c.draw_rect(Rect2(cc - Vector2(9, 26), Vector2(18, 52)), Color(0.85, 0.15, 0.12))
	c.draw_rect(Rect2(cc - Vector2(26, 9), Vector2(52, 18)), Color(0.85, 0.15, 0.12))
	c.draw_rect(Rect2(Vector2(rr.end.x - rr.size.x * 0.3, rr.position.y + 4.0), Vector2(10, rr.size.y - 8.0)), Color(0.3, 0.5, 1.0))
	c.draw_rect(rr, INK, false, 3.5)


static func _patrol(c: CanvasItem, r: Rect2) -> void:
	var rr := r.grow(-6.0)
	_shadow(c, rr)
	c.draw_rect(rr, Color(0.12, 0.14, 0.2))
	c.draw_rect(Rect2(rr.position + Vector2(0, rr.size.y * 0.3), Vector2(rr.size.x, rr.size.y * 0.4)), Color(0.95, 0.95, 0.95))
	c.draw_rect(Rect2(rr.position + Vector2(10, rr.size.y * 0.18), Vector2(rr.size.x - 20.0, rr.size.y * 0.12)), Color(0.3, 0.45, 0.6))
	c.draw_rect(Rect2(rr.position + Vector2(10, rr.size.y * 0.72), Vector2(rr.size.x - 20.0, rr.size.y * 0.1)), Color(0.3, 0.45, 0.6))
	var mid := rr.position + Vector2(rr.size.x * 0.5, rr.size.y * 0.45)
	c.draw_rect(Rect2(mid - Vector2(rr.size.x * 0.4, 6), Vector2(rr.size.x * 0.4, 12)), Color(0.9, 0.15, 0.12))
	c.draw_rect(Rect2(mid - Vector2(0, 6), Vector2(rr.size.x * 0.4, 12)), Color(0.15, 0.35, 0.95))
	c.draw_string(ThemeDB.fallback_font, rr.position + Vector2(0, rr.size.y * 0.62), "POLICE", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 14, Color(0.1, 0.12, 0.2))
	c.draw_rect(rr, INK, false, 3.5)


static func _runway(c: CanvasItem, r: Rect2) -> void:
	var white := Color(0.94, 0.94, 0.9, 0.9)
	c.draw_line(Vector2(r.position.x, r.position.y + 18.0), Vector2(r.end.x, r.position.y + 18.0), white, 5.0)
	c.draw_line(Vector2(r.position.x, r.end.y - 18.0), Vector2(r.end.x, r.end.y - 18.0), white, 5.0)
	var my := r.position.y + r.size.y * 0.5
	var x := r.position.x + TILE * 7.0
	while x < r.end.x - TILE * 7.0:
		c.draw_rect(Rect2(x, my - 6.0, TILE * 1.8, 12.0), white)
		x += TILE * 3.2
	for end in [r.position.x + TILE * 0.8, r.end.x - TILE * 4.0]:
		for k in 8:
			c.draw_rect(Rect2(end, r.position.y + 40.0 + float(k) * (r.size.y - 80.0) / 8.0, TILE * 3.2, (r.size.y - 80.0) / 16.0), white)
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(r.position.x + TILE * 4.4, my + 24.0), "09", HORIZONTAL_ALIGNMENT_CENTER, TILE * 2.0, 64, white)
	c.draw_string(font, Vector2(r.end.x - TILE * 6.6, my + 24.0), "27", HORIZONTAL_ALIGNMENT_CENTER, TILE * 2.0, 64, white)
	for k in 9:    # skid marks
		var sx := r.position.x + TILE * (9.0 + float(k) * 1.3)
		c.draw_line(Vector2(sx, my - 70.0 + float(k % 3) * 10.0), Vector2(sx + TILE * 2.0, my - 66.0 + float(k % 3) * 10.0), Color(0.08, 0.08, 0.08, 0.35), 6.0)


## An airliner nose east (or a small prop plane): the wings, the tail, the fuselage with its windows and a stripe of `col`, the engines.
static func _plane(c: CanvasItem, r: Rect2, col: Color, small: bool) -> void:
	var cy := r.position.y + r.size.y * 0.5
	var L := r.size.x
	var x0 := r.position.x
	var fw := r.size.y * (0.14 if not small else 0.16)
	var wing := PackedVector2Array([Vector2(x0 + L * 0.42, cy - fw * 0.4), Vector2(x0 + L * 0.58, cy - fw * 0.4), Vector2(x0 + L * 0.42, r.position.y), Vector2(x0 + L * 0.34, r.position.y),
		Vector2(x0 + L * 0.34, r.end.y), Vector2(x0 + L * 0.42, r.end.y), Vector2(x0 + L * 0.58, cy + fw * 0.4), Vector2(x0 + L * 0.42, cy + fw * 0.4)])
	if small:
		wing = PackedVector2Array([Vector2(x0 + L * 0.5, r.position.y), Vector2(x0 + L * 0.62, r.position.y), Vector2(x0 + L * 0.62, r.end.y), Vector2(x0 + L * 0.5, r.end.y)])
	var tail := PackedVector2Array([Vector2(x0 + L * 0.1, cy), Vector2(x0, cy - r.size.y * 0.2), Vector2(x0 + L * 0.06, cy - r.size.y * 0.2), Vector2(x0 + L * 0.2, cy),
		Vector2(x0 + L * 0.06, cy + r.size.y * 0.2), Vector2(x0, cy + r.size.y * 0.2)])
	var body := Rect2(x0 + L * 0.03, cy - fw * 0.5, L * 0.92, fw)
	for poly in [wing, tail]:
		var sh := PackedVector2Array()
		for q in poly:
			sh.append(q + Vector2(22, 30))
		c.draw_colored_polygon(sh, Color(0, 0, 0, 0.22))
	c.draw_rect(Rect2(body.position + Vector2(22, 30), body.size), Color(0, 0, 0, 0.22))
	c.draw_colored_polygon(wing, Color(0.82, 0.84, 0.86))
	var wl := wing.duplicate()
	wl.append(wing[0])
	c.draw_polyline(wl, INK, 4.0)
	c.draw_colored_polygon(tail, Color(0.86, 0.87, 0.88))
	var tl := tail.duplicate()
	tl.append(tail[0])
	c.draw_polyline(tl, INK, 4.0)
	if not small:
		for ey in [r.position.y + r.size.y * 0.22, r.end.y - r.size.y * 0.22]:
			var eng := Rect2(x0 + L * 0.44, ey - fw * 0.28, L * 0.1, fw * 0.56)
			c.draw_rect(eng, Color(0.42, 0.44, 0.47))
			c.draw_rect(eng, INK, false, 3.0)
	c.draw_rect(body, Color(0.95, 0.95, 0.93))
	c.draw_circle(Vector2(body.end.x, cy), fw * 0.5, Color(0.95, 0.95, 0.93))
	c.draw_arc(Vector2(body.end.x, cy), fw * 0.5, -PI * 0.5, PI * 0.5, 12, INK, 4.0)
	c.draw_line(Vector2(body.position.x + L * 0.04, cy), Vector2(body.end.x - 6.0, cy), col, fw * 0.22)
	if not small:
		var wx := body.position.x + L * 0.08
		while wx < body.end.x - L * 0.06:
			c.draw_rect(Rect2(wx, cy - fw * 0.36, 6.0, 7.0), Color(0.2, 0.3, 0.42))
			wx += 18.0
	c.draw_rect(Rect2(body.end.x - fw * 0.3, cy - fw * 0.3, fw * 0.22, fw * 0.6), Color(0.2, 0.3, 0.42))
	c.draw_line(body.position, Vector2(body.end.x, body.position.y), INK, 4.0)
	c.draw_line(Vector2(body.position.x, body.end.y), body.end, INK, 4.0)
	c.draw_line(body.position, Vector2(body.position.x, body.end.y), INK, 4.0)
	if small:
		c.draw_line(Vector2(body.end.x + fw * 0.5, cy - fw * 1.6), Vector2(body.end.x + fw * 0.5, cy + fw * 1.6), INK, 6.0)


## The stadium bowl: the outer wall's ring and its gates, the seats (rows in two club colours, the aisles), the track and the pitch with its lines and goals.
static func _bowl(c: CanvasItem, r: Rect2) -> void:
	var cc := r.get_center()
	var R := r.size * 0.5
	var ring := func(e: float, col: Color, w: float) -> void:
		var pts := PackedVector2Array()
		for k in 97:
			var a := float(k) / 96.0 * TAU
			pts.append(cc + Vector2(cos(a) * R.x, sin(a) * R.y) * e)
		c.draw_polyline(pts, col, w)
	var disc := func(e: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for k in 96:
			var a := float(k) / 96.0 * TAU
			pts.append(cc + Vector2(cos(a) * R.x, sin(a) * R.y) * e)
		c.draw_colored_polygon(pts, col)
	disc.call(1.12, Color(0.6, 0.6, 0.58))    # (the plaza round the wall, smooth over the tiles' steps)
	disc.call(0.995, Color(0.55, 0.55, 0.57))
	disc.call(0.9, Color(0.66, 0.65, 0.62))
	disc.call(0.72, Color(0.36, 0.38, 0.42))
	var e := 0.715
	var k2 := 0
	while e > 0.475:    # the rows of seats
		ring.call(e, Color(0.72, 0.18, 0.18) if (k2 / 3) % 2 == 0 else Color(0.92, 0.92, 0.9), 9.0)
		e -= 0.0165
		k2 += 1
	disc.call(0.47, Color(0.66, 0.36, 0.26))
	disc.call(0.4, Color(0.3, 0.52, 0.24))
	var pitch := Rect2(cc - R * 0.4 * Vector2(0.78, 0.66), R * 0.8 * Vector2(0.78, 0.66))
	var sw := pitch.size.x / 10.0
	for k in 10:
		if k % 2 == 0:
			c.draw_rect(Rect2(pitch.position + Vector2(sw * k, 0), Vector2(sw, pitch.size.y)), Color(0.34, 0.58, 0.27))
	var white := Color(0.95, 0.95, 0.92, 0.9)
	c.draw_rect(pitch, white, false, 5.0)
	c.draw_line(Vector2(cc.x, pitch.position.y), Vector2(cc.x, pitch.end.y), white, 5.0)
	c.draw_arc(cc, pitch.size.y * 0.18, 0, TAU, 32, white, 5.0)
	for side in [-1.0, 1.0]:
		var gx: float = cc.x + side * pitch.size.x * 0.5
		var box := Rect2(Vector2(gx - (pitch.size.x * 0.16 if side > 0 else 0.0), cc.y - pitch.size.y * 0.3), Vector2(pitch.size.x * 0.16, pitch.size.y * 0.6))
		c.draw_rect(box, white, false, 5.0)
		var goal := Rect2(Vector2(gx + (0.0 if side > 0 else -24.0), cc.y - 60.0), Vector2(24, 120))
		c.draw_rect(goal, Color(0.95, 0.95, 0.95, 0.5))
		c.draw_rect(goal, INK, false, 3.0)
	for k in 8:    # the aisles: steps of light concrete
		var a := float(k) * PI / 4.0
		var d := Vector2(cos(a) * R.x, sin(a) * R.y)
		c.draw_line(cc + d * 0.47, cc + d * 0.72, Color(0.78, 0.77, 0.74), TILE * 1.3)
		var steps := 6
		for s in steps:
			var q := cc + d * (0.49 + float(s) * 0.04)
			var n := Vector2(-d.y, d.x).normalized() * TILE * 0.62
			c.draw_line(q - n, q + n, Color(0.55, 0.55, 0.52), 3.0)
	ring.call(1.0, INK, 6.0)
	ring.call(0.9, INK, 4.0)
	ring.call(0.72, INK, 4.0)
	ring.call(0.47, INK, 3.0)
	var font := ThemeDB.fallback_font
	for k in 4:    # the gates
		var a := float(k) * PI * 0.5
		var q := cc + Vector2(cos(a) * R.x, sin(a) * R.y) * 0.95
		c.draw_circle(q, TILE * 0.5, Color(0.95, 0.8, 0.2, 0.6))
		c.draw_string(font, q + Vector2(-60, -TILE * 0.9), "GATE %s" % ["E", "S", "W", "N"][k], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(0.95, 0.9, 0.7))


static func _stall(c: CanvasItem, r: Rect2, col: Color) -> void:
	var rr := r.grow(-4.0)
	_shadow(c, rr)
	c.draw_rect(rr, Color(0.95, 0.93, 0.88))
	var n := 5
	for k in n:
		if k % 2 == 0:
			c.draw_rect(Rect2(rr.position + Vector2(rr.size.x * k / n, 0), Vector2(rr.size.x / n, rr.size.y * 0.55)), col)
	c.draw_rect(Rect2(rr.position + Vector2(8, rr.size.y * 0.62), Vector2(rr.size.x - 16.0, rr.size.y * 0.28)), Color(0.55, 0.38, 0.22))
	c.draw_rect(rr, INK, false, 3.0)


static func _excavator(c: CanvasItem, r: Rect2) -> void:
	_shadow(c, r, 14.0)
	var y := Color(0.95, 0.72, 0.12)
	c.draw_rect(Rect2(r.position + Vector2(0, 8), Vector2(r.size.x * 0.7, 26)), Color(0.18, 0.18, 0.2))
	c.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 34.0), Vector2(r.size.x * 0.7, 26)), Color(0.18, 0.18, 0.2))
	var body := Rect2(r.position + Vector2(18, 30), Vector2(r.size.x * 0.55, r.size.y - 60.0))
	c.draw_rect(body, y)
	c.draw_rect(Rect2(body.position + Vector2(10, 10), Vector2(body.size.x * 0.4, body.size.y * 0.45)), Color(0.25, 0.35, 0.45))
	c.draw_rect(body, INK, false, 3.5)
	var a := body.get_center() + Vector2(body.size.x * 0.4, 0)
	var b := Vector2(r.end.x - 20.0, r.position.y + r.size.y * 0.35)
	c.draw_line(a, b, INK, 22.0)
	c.draw_line(a, b, y, 15.0)
	c.draw_rect(Rect2(b - Vector2(16, 22), Vector2(34, 44)), Color(0.35, 0.35, 0.36))
	c.draw_rect(Rect2(b - Vector2(16, 22), Vector2(34, 44)), INK, false, 3.0)


static func _scrap(c: CanvasItem, r: Rect2) -> void:
	var cc := r.get_center()
	var pts := PackedVector2Array()
	for k in 11:
		var a := float(k) / 11.0 * TAU
		var f := 0.75 + 0.25 * fposmod(sin(float(k) * 12.9898 + r.position.x) * 43758.5453, 1.0)
		pts.append(cc + Vector2(cos(a) * r.size.x * 0.48, sin(a) * r.size.y * 0.46) * f)
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(10, 14))
	c.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
	c.draw_colored_polygon(pts, Color(0.48, 0.34, 0.24))
	for k in 9:
		var q := cc + Vector2(fposmod(float(k) * 37.1, r.size.x * 0.6) - r.size.x * 0.3, fposmod(float(k) * 53.7, r.size.y * 0.6) - r.size.y * 0.3)
		c.draw_line(q, q + Vector2(26, (k % 3 - 1) * 14.0), [Color(0.62, 0.6, 0.58), Color(0.6, 0.3, 0.18), Color(0.3, 0.4, 0.5)][k % 3], 7.0)
	var pl := pts.duplicate()
	pl.append(pts[0])
	c.draw_polyline(pl, INK, 3.5)
