## The base layout of a claimed house (One House, plan 1.6): everything the colony's machinery needs to run a generated base, as data made from the
## house's lot, its doors and rooms and the free tiles round it. Pure and deterministic (no dice, no sim): `BaseLayout.make(town, house_id, opts)` and
## `BaseLayout.validate(layout, town)` (a list of problems, empty is good).
##
## The perimeter runs on the BORDER of the lot (the lot's outer ring of tiles); the yard is the lot inside it; the house stands in the yard. The front
## is the side the house's front door is on: its fence has the gate in front of the door. Slots (plan 2.2, scripts/town/perimeter.gd): the barred
## doors (door slots: a plank upgrade), the fence sections (the front ones next to the gate first, then the rest of the front, the sides, the back),
## the gate, two towers (inner corners) and two floodlights (inner side tiles). Each slot is also a Build plot (`plots`, id == the slot's id, kind
## "slot"); the kits are the catalogue entries of `buildings` (id "kit_<kit>", `slot_kit` = the kit id; a fence slot has its own, "kit_<kit>@<slot id>", priced by its length, and an
## upgrade entry "kit_<strong kit>_up@<slot id>" that makes the plain fence that stands on it strong). The tiles of the ring that are not free (a neighbour's wall, a tree) are not
## slots: the runs of free tiles are split into sections of at most `section_max` tiles (12: about ten sections round a lot of 28 by 22; ROOMY HOUSES made the start lot four tiles wider, and
## the sections were tried at 14 tiles to keep their number: the lab lost a night in one run of three with them, as against one in twelve with sections of 12). What the player orders is a PROJECT
## (base_kits.json: the slots of a `role`, scripts/town/perimeter.gd), not a slot.
##
## Added to the plan's shape (nothing changed): `doors[i]` has "side", "name", "dead_places", "slot" (the door's plank slot id); `slots[i]` has
## "role" (the unlock table's key), "center" (Vector2), "work" (Vector2: where the builders stand), "door" (a door slot's door id), "tiles" (the
## rect's tiles as indexes); `kits` is the kit table of assets/data/base_kits.json; `gate` is the gate slot's id or ""; `spawn_range` is the
## [low, high] distance the spawns were chosen in; `inner` is the yard's inner ring (the Rect2i of tiles just inside the border).
extends RefCounted

const KITS_PATH := "res://assets/data/base_kits.json"
const STATIONS_PATH := "res://assets/data/stations.json"
const VERSION := 1
const SLOT_KINDS := ["fence", "gate", "tower", "floodlight", "door"]
## The stations the base has, and the props it draws (the interior's ids).
const STATIONS := ["bench", "builders", "radio", "watch", "infirmary"]
const PROPS := ["bed", "stash", "radio", "bench"]
## The rooms each prop likes (the first name that is in the house, else the largest free room).
const PROP_ROOMS := {"bed": ["bedroom", "side"], "stash": ["kitchen", "pantry", "storeroom"], "radio": ["study", "living room", "front room", "shop floor"],
	"bench": ["utility", "garage", "workshop", "living room", "front room", "shop floor", "kitchen"]}
const COMPASS := {"N": "North", "E": "East", "S": "South", "W": "West"}
## What the stations say in a town of one house (the school's words are about its noon call and its tower).
const TOWN_BLURBS := {
	"radio": "Keeps an ear on the set. The people you find in the town answer on it.",
	"watch": "Watches the street from the yard and, once the dead come every night, tells the crew two hours before dusk what tonight looks like.",
}
## The cost of looking round a door for a free tile: how far from the wanted one a slot may slide.
const SLIDE := 3


## The grid of the town for the free-tile tests.
class Grid:
	extends RefCounted
	var w := 0
	var h := 0
	var sz: Array
	var sp: Array

	func open(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= w or y >= h:
			return false
		var i := y * w + x
		return int(sz[i]) == 0 and int(sp[i]) == 0

	func open_f(x: float, y: float) -> bool:
		return open(floori(x), floori(y))


# ------------------------------------------------------------------ the data --

## {"kits", "unlock", "layout", "projects"} of assets/data/base_kits.json (a missing file gives empty tables: the layout then has no kits and validate says so).
static func load_kits() -> Dictionary:
	var out := {"kits": {}, "unlock": {}, "layout": {}, "projects": []}
	if not FileAccess.file_exists(KITS_PATH):
		return out
	var raw = JSON.parse_string(FileAccess.get_file_as_string(KITS_PATH))
	if raw is Dictionary:
		for k in out:
			if k == "projects":
				if raw.get(k) is Array:
					out[k] = raw[k]
			elif raw.get(k) is Dictionary:
				out[k] = raw[k]
	return out


static func _num(d: Dictionary, key: String, fallback: float) -> float:
	return float(d.get(key, fallback))


## The id of the project (base_kits.json) that builds the slots of this role ("" for none; the upgrade project has no slots of its own).
static func project_of(role: String, table: Dictionary) -> String:
	for p in table.get("projects", []):
		if not bool(p.get("upgrade", false)) and Array(p.get("roles", [])).has(role):
			return String(p.id)
	return ""


static func _grid(town: Dictionary) -> Grid:
	var g := Grid.new()
	g.w = int(town.data.W)
	g.h = int(town.data.H)
	g.sz = town.data.solidZ
	g.sp = town.data.solidP
	return g


static func _center_of(r: Rect2i) -> Vector2:
	return Vector2(r.position) + Vector2(r.size) * 0.5


static func _tile_center(t: Vector2i) -> Vector2:
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)


static func _pt(v: Vector2) -> Array:
	return [v.x, v.y]


# ---------------------------------------------------------------------- make --

## The layout of house `house_id` of `town` (a TownGen.make result). `opts`: "kits" (a table of base_kits.json's shape, for a test), "spawn_range" ([lo, hi]).
static func make(town: Dictionary, house_id: int, opts: Dictionary = {}) -> Dictionary:
	var h: Dictionary = town.houses[house_id]
	var grid := _grid(town)
	var table: Dictionary = opts.get("kits", load_kits())
	var kits: Dictionary = table.get("kits", {})
	var unlock: Dictionary = table.get("unlock", {})
	var knobs: Dictionary = table.get("layout", {})
	var lot: Rect2i = h.lot
	var rect: Rect2i = h.rect
	var front := String(h.front)
	var front_south := front == "S"
	var lx := lot.position.x
	var ly := lot.position.y
	var lw := lot.size.x
	var lh := lot.size.y
	var section_max := int(_num(knobs, "section_max", 5.0))
	var gate_w := int(_num(knobs, "gate_width", 3.0))
	var door_hp := _num(knobs, "door_hp", 90.0)
	var ring_tiles := 0
	var ring_free := 0
	for x in lw:
		for y in lh:
			if x == 0 or y == 0 or x == lw - 1 or y == lh - 1:
				ring_tiles += 1
				if grid.open(lx + x, ly + y):
					ring_free += 1
	var fy := ly + lh - 1 if front_south else ly
	var by := ly if front_south else ly + lh - 1
	var fo := 1 if front_south else -1
	var xl := lx + 1
	var xr := lx + lw - 2
	var yt := ly + 1
	var yb := ly + lh - 2
	var yf := yb if front_south else yt
	var ybk := yt if front_south else yb

	# the doors of the house on its outer wall: the front one first
	var ext: Array = []
	for d in h.doors:
		if bool(d.exterior):
			ext.append(d)
	ext.sort_custom(func(a, b): return (0 if String(a.side) == front else 1) < (0 if String(b.side) == front else 1))
	var front_door: Dictionary = ext[0] if not ext.is_empty() else {}

	var slots: Array = []
	var doors: Array = []
	var taken := {}    # tile index -> slot id (the rects of every slot)

	# the barred doors and their plank slots
	var door_ids := ["door_front", "door_back"]
	for i in mini(ext.size(), 2):
		var d: Dictionary = ext[i]
		var tiles: Array = d.tiles
		var out_t: Vector2i = d.out
		var inside: Vector2i = d["in"]
		var side := String(d.side)
		var o := Vector2i(signi(out_t.x - inside.x), signi(out_t.y - inside.y))
		var r := Rect2i(tiles[0], Vector2i(1, 1))
		for t in tiles:
			r = r.expand(t)
		var places: Array = []
		for t in tiles:
			var cx := float(t.x) + 0.5
			var cy := float(t.y) + 0.5
			var px := cx + float(o.x) * 1.0
			var py := cy + float(o.y) * 1.0
			var ax := cx + float(o.x) * 2.0
			var ay := cy + float(o.y) * 2.0
			if grid.open_f(px, py) and grid.open_f(ax, ay):
				places.append({"x": px, "y": py, "ax": ax, "ay": ay, "face": _toward(o)})
		var nm := "Front door" if i == 0 else "Back door"
		var tile_list: Array = []
		for t in tiles:
			tile_list.append(Vector2i(t))
		doors.append({"id": door_ids[i], "name": nm, "side": side, "tiles": tile_list, "hp": door_hp, "dead_places": places, "slot": "slot_" + door_ids[i]})
		slots.append(_slot("slot_" + door_ids[i], "door", nm, r, "h" if side == "N" or side == "S" else "v", side, "door", ["door_plank"], places, kits, unlock, _tile_center(_nearest_open(grid, inside, Rect2i(h.rect))), grid, String(door_ids[i])))
		for t in tiles:
			taken[int(t.y) * grid.w + int(t.x)] = "slot_" + door_ids[i]

	# the front row of the border: the gate in front of the door, the fence either side
	var gate_x0 := -1
	if not front_door.is_empty():
		var ft: Array = front_door.tiles
		var minx := int(ft[0].x)
		for t in ft:
			minx = mini(minx, int(t.x))
		var want := clampi(minx, lx + 2, lx + lw - gate_w - 2)
		for slide in range(0, SLIDE + 1):
			for sgn in [1, -1]:
				var cand: int = want + slide * sgn
				if cand < lx + 2 or cand > lx + lw - gate_w - 2 or gate_x0 >= 0:
					continue
				var ok := true
				for k in gate_w:
					if not grid.open(cand + k, fy):
						ok = false
				if ok:
					gate_x0 = cand
	var front_name: String = COMPASS[front]
	var gate_id := ""
	if gate_x0 >= 0:
		gate_id = "slot_gate"
		var gr := Rect2i(gate_x0, fy, gate_w, 1)
		var gp := _places(grid, gr, "h", fo, _num(kits.get("gate", {}), "stand", 0.55))
		slots.append(_slot(gate_id, "gate", "Front gate", gr, "h", front, "gate", ["gate"], gp, kits, unlock, Vector2(float(gate_x0) + float(gate_w) * 0.5, float(yf) + 0.5), grid))
		_take(taken, grid, gr, gate_id)
	var fence_n := 0
	var front_runs: Array = []
	if gate_x0 >= 0:
		front_runs.append(_free_run(grid, lx, gate_x0 - 1, fy, true))
		front_runs.append(_free_run(grid, gate_x0 + gate_w, lx + lw - 1, fy, true))
	else:
		front_runs.append(_free_run(grid, lx, lx + lw - 1, fy, true))
	for ri in front_runs.size():
		for run in front_runs[ri]:
			var sizes := _chunks(run.size(), section_max)
			var at := 0
			for ci in sizes.size():
				var x0: int = run[at]
				var r := Rect2i(x0, fy, sizes[ci], 1)
				at += sizes[ci]
				if sizes[ci] < 2:
					continue
				# the section next to the gate is "near": the first of the one after it, the last of the one before it
				var near: bool = gate_x0 >= 0 and ((ri == 0 and r.end.x == gate_x0) or (ri == 1 and r.position.x == gate_x0 + gate_w))
				fence_n += 1
				var id := "slot_front_%d" % fence_n
				var nm := "%s fence" % front_name
				if front_runs.size() > 1 or sizes.size() > 1:
					nm = "%s fence, %s" % [front_name, "west part" if r.position.x < lx + lw / 2 else "east part"]
				var places := _places(grid, r, "h", fo, _num(kits.get("fence", {}), "stand", 0.55))
				slots.append(_slot(id, "fence", nm, r, "h", front, "front_near" if near else "front", ["fence", "fence_strong"], places, kits, unlock, Vector2(_center_of(r).x, float(yf) + 0.5), grid))
				_take(taken, grid, r, id)

	# the back row, then the two sides (the corners belong to the rows)
	var back := "N" if front_south else "S"
	var bo := -fo
	var back_runs := _free_run(grid, lx, lx + lw - 1, by, true)
	var bn := 0
	for run in back_runs:
		var sizes := _chunks(run.size(), section_max)
		var at := 0
		for ci in sizes.size():
			var r := Rect2i(int(run[at]), by, sizes[ci], 1)
			at += sizes[ci]
			if sizes[ci] < 2:
				continue
			bn += 1
			var nm := "%s fence" % COMPASS[back]
			if back_runs.size() > 1 or sizes.size() > 1:
				nm = "%s fence, %s" % [COMPASS[back], "west part" if _center_of(r).x < float(lx) + float(lw) * 0.5 - 1.0 else ("east part" if _center_of(r).x > float(lx) + float(lw) * 0.5 + 1.0 else "middle")]
			var places := _places(grid, r, "h", bo, _num(kits.get("fence", {}), "stand", 0.55))
			var id := "slot_back_%d" % bn
			slots.append(_slot(id, "fence", nm, r, "h", back, "back", ["fence", "fence_strong"], places, kits, unlock, Vector2(_center_of(r).x, float(ybk) + 0.5), grid))
			_take(taken, grid, r, id)
	for side_def in [["W", lx, -1], ["E", lx + lw - 1, 1]]:
		var col: int = side_def[1]
		var runs := _free_run(grid, ly + 1, ly + lh - 2, col, false)
		var n := 0
		for run in runs:
			var sizes := _chunks(run.size(), section_max)
			var at := 0
			for ci in sizes.size():
				var r := Rect2i(col, int(run[at]), 1, sizes[ci])
				at += sizes[ci]
				if sizes[ci] < 2:
					continue
				n += 1
				var nm := "%s fence" % COMPASS[side_def[0]]
				if runs.size() > 1 or sizes.size() > 1:
					nm = "%s fence, %s" % [COMPASS[side_def[0]], "north part" if _center_of(r).y < float(ly) + float(lh) * 0.5 - 1.0 else ("south part" if _center_of(r).y > float(ly) + float(lh) * 0.5 + 1.0 else "middle")]
				var places := _places(grid, r, "v", int(side_def[2]), _num(kits.get("fence", {}), "stand", 0.55))
				var id := "slot_%s_%d" % [String(side_def[0]).to_lower() + "side", n]
				slots.append(_slot(id, "fence", nm, r, "v", String(side_def[0]), "side", ["fence", "fence_strong"], places, kits, unlock, Vector2(float(xl if String(side_def[0]) == "W" else xr) + 0.5, _center_of(r).y), grid))
				_take(taken, grid, r, id)

	# the two towers (inner corners: front-left and back-right) and the two floodlights (the middle of the inner side columns)
	var ymid := (yt + yb) / 2
	var corner_tiles := [Vector2i(xl, yf), Vector2i(xr, ybk)]
	var corner_posts := [Vector2i(xl, yf + (-1 if front_south else 1)), Vector2i(xr, ybk + (1 if front_south else -1))]
	var tower_ids: Array = []
	var reserved := {}
	for i in 2:
		var t: Vector2i = _free_near(grid, corner_tiles[i], reserved, taken, Rect2i(xl, yt, xr - xl + 1, yb - yt + 1), rect)
		if t.x < 0:
			continue
		reserved[t] = true
		var id := "slot_tower_%d" % (i + 1)
		var corner_side: String = (String(front) if i == 0 else back)
		var nm := "%s-%s tower" % [COMPASS[corner_side], "west" if i == 0 else "east"]
		var r := Rect2i(t, Vector2i(1, 1))
		slots.append(_slot(id, "tower", nm, r, "h", corner_side, "tower" if i == 0 else "tower2", ["tower"], [], kits, unlock, _tile_center(corner_posts[i]), grid))
		_take(taken, grid, r, id)
		tower_ids.append(id)
	var light_tiles := [Vector2i(xl, ymid), Vector2i(xr, ymid)]
	for i in 2:
		var t: Vector2i = _free_near(grid, light_tiles[i], reserved, taken, Rect2i(xl, yt, xr - xl + 1, yb - yt + 1), rect)
		if t.x < 0:
			continue
		reserved[t] = true
		var id := "slot_light_%d" % (i + 1)
		var nm := "%s floodlight" % ("West" if i == 0 else "East")
		var r := Rect2i(t, Vector2i(1, 1))
		slots.append(_slot(id, "floodlight", nm, r, "v", "W" if i == 0 else "E", "floodlight", ["floodlight"], [], kits, unlock, _tile_center(Vector2i(t.x, t.y + 1)), grid))
		_take(taken, grid, r, id)

	# the posts: along the inner ring, clear of the gate's way, the towers and the floodlights; the towers' own
	var gate_c := Vector2(float(gate_x0) + float(gate_w) * 0.5, float(fy) + 0.5) if gate_x0 >= 0 else (_center_of(rect) + Vector2(0.0, float(fo) * float(rect.size.y) * 0.5))
	var posts: Array = []
	var post_tiles := {}
	for i in tower_ids.size():
		var idx: int = int(String(tower_ids[i]).get_slice("_", 2)) - 1
		var t: Vector2i = corner_posts[idx]
		if grid.open(t.x, t.y) and not reserved.has(t):
			post_tiles[t] = true
			posts.append(_post(t, "On the tower", tower_ids[i], lx, ly, lw, lh))
	var ring: Array = _ring(xl, xr, yt, yb)
	# (a bigger lot has a longer ring: a post every four tiles, or farther apart where that would be more than about ten of them)
	var spacing := maxi(4, ceili(float(ring.size()) / 10.0))
	var min_posts := int(_num(knobs, "posts_min", 8.0))
	while true:
		var picked: Array = []
		for k in range(0, ring.size(), spacing):
			var t: Vector2i = ring[k]
			if reserved.has(t) or post_tiles.has(t) or not grid.open(t.x, t.y):
				continue
			if t.y == yf and gate_x0 >= 0 and t.x >= gate_x0 - 1 and t.x <= gate_x0 + gate_w:
				continue
			picked.append(t)
		if post_tiles.size() + picked.size() >= min_posts or spacing <= 2:
			for t in picked:
				var sid := _slot_at_border(taken, grid, t, lx, ly, lw, lh)
				posts.append(_post(t, "Holding the %s" % _compass_of_tile(t, lx, ly, lw, lh, true).to_lower() + " fence", sid, lx, ly, lw, lh))
			break
		spacing -= 1
	posts.sort_custom(func(a, b):
		var da := Vector2(float(a.pos[0]), float(a.pos[1])).distance_to(gate_c)
		var db := Vector2(float(b.pos[0]), float(b.pos[1])).distance_to(gate_c)
		return da < db or (da == db and (a.pos[0] < b.pos[0] or (a.pos[0] == b.pos[0] and a.pos[1] < b.pos[1]))))
	for i in posts.size():
		posts[i]["id"] = "post_%d" % (i + 1)
		posts[i]["name"] = "Post %d" % (i + 1)
	for s in slots:
		if String(s.kind) == "tower":
			for po in posts:
				if String(po.slot) == String(s.id):
					s["post"] = String(po.id)
		elif String(s.kind) == "fence" or String(s.kind) == "gate":
			for po in posts:
				if String(po.slot) == String(s.id) and String(s.post) == "":
					s["post"] = String(po.id)

	# the interior: the four props in the house's rooms
	var avoid := {}
	var claim_spot := Vector2.ZERO
	var yard_middle := _center_of(lot)
	var doorway := {}
	for d in h.doors:
		for t in d.tiles:
			avoid[Vector2i(t)] = true
			doorway[Vector2i(t)] = true
		var o: Vector2i = d.out
		var inn: Vector2i = d["in"]
		for c in [o, inn]:
			avoid[Vector2i(c)] = true
	if not front_door.is_empty():
		claim_spot = _tile_center(_nearest_open(grid, front_door["in"], Rect2i(h.rect)))
		yard_middle = _tile_center(front_door.out)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				avoid[Vector2i(front_door["in"].x + dx, front_door["in"].y + dy)] = true
	var interior: Array = []
	var used := {}
	# (the bench and the radio are worked from in front of them: the tile in front of each is kept free, `fronts`, so that whoever works there does not stand in the furniture)
	var fronts := {}
	for pid in ["bed", "stash", "bench", "radio"]:    # (the bench first: the radio is then put as far from it as the room allows, so that their seats are not one crowd)
		var wide := 2 if pid == "bench" else 1
		var room_i := _room_for(town, h, String(pid), grid, avoid, used, wide)
		if room_i < 0:
			continue
		var room_rect: Rect2i = town.rooms[room_i].rect
		var away: Vector2 = fronts.get("bench", Vector2(-1.0, -1.0)) if pid == "radio" else Vector2(-1.0, -1.0)
		var tile := _spare(grid, room_rect, avoid, used, wide, pid == "bench" or pid == "radio", away)
		if tile.x < 0:
			tile = _spare(grid, room_rect, avoid, used, wide, false, away)
		for k in wide:
			used[Vector2i(tile.x + k, tile.y)] = true
		if pid == "bench" or pid == "radio":
			# (the stand may be beside a doorway: a small room has no better place; it is never in one)
			var stand := _stand_for(grid, doorway, used, tile, wide, wide)
			var offsets: Array = []
			if stand.x < 0 and pid == "bench":
				# no two free tiles in a row: one person at the bench, the second seat on any free tile beside the first
				stand = _stand_for(grid, doorway, used, tile, wide, 1)
				if stand.x >= 0:
					for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var other: Vector2i = stand + dv
						if offsets.is_empty() and grid.open(other.x, other.y) and not doorway.has(other) and not used.has(other) and not (other.y == tile.y and other.x >= tile.x and other.x < tile.x + wide):
							offsets = [Vector2.ZERO, Vector2(dv)]
							used[other] = true
			if stand.x >= 0:
				for k in (wide if offsets.is_empty() else 1):
					used[Vector2i(stand.x + k, stand.y)] = true
				fronts[String(pid)] = _tile_center(stand)
				if pid == "bench" and not offsets.is_empty():
					fronts["bench_offsets"] = offsets
		# (a prop is drawn about its pos: the bench is two tiles wide, so its middle is the line between them)
		var at := _tile_center(tile) + (Vector2(0.5, 0.0) if wide == 2 else Vector2.ZERO)
		interior.append({"id": pid, "kind": pid, "pos": at, "room": room_i, "face": "S"})
	interior.sort_custom(func(a, b): return PROPS.find(String(a.id)) < PROPS.find(String(b.id)))
	var prop_at := {}
	for p in interior:
		prop_at[String(p.id)] = p
		if fronts.has(String(p.id)):
			prop_at[String(p.id)]["front"] = fronts[String(p.id)]
	if fronts.has("bench_offsets") and prop_at.has("bench"):
		prop_at["bench"]["seat_offsets"] = fronts["bench_offsets"]

	# the stations and the resting spots (stations.json's words, this base's places)
	var stations: Array = _stations(grid, town, h, interior, prop_at, slots, tower_ids, yard_middle, front_door, xl, xr, yt, yb, used, avoid)
	var rest := _rest(grid, yard_middle, front_door, xl, xr, yt, yb, posts, town, h, avoid, used)

	# the plots (a slot is a Build plot) and the catalogue entries of the kits the slots use
	# (a fence section is priced by its length: the kit's numbers are for `per_tiles` tiles, so that a ring costs and holds the same however it is cut up; the dearer kit also
	# has an UPGRADE entry for the slot, the difference in price, which the Build module lets be ordered on a plot where the cheaper one stands)
	var plots: Array = []
	var buildings: Array = []
	var made := {}
	var per_tiles := maxf(1.0, _num(knobs, "per_tiles", 5.0))
	for s in slots:
		var r: Rect2i = s.rect
		var kit_buildings: Array = []
		var sized := String(s.kind) == "fence"
		var share := float(r.size.x * r.size.y) / per_tiles if sized else 1.0
		var plain_id := ""
		for k in s.kits:
			var kd: Dictionary = kits[k]
			var bid := "kit_%s@%s" % [k, s.id] if sized else "kit_" + String(k)
			if not made.has(bid):
				made[bid] = true
				buildings.append(_entry(bid, String(k), kd, share))
			kit_buildings.append(bid)
			if plain_id == "":
				plain_id = bid
		if sized and s.kits.size() > 1:
			# the upgrade of the first kit to the second (a plain fence made strong)
			var strong_k := String(s.kits[1])
			var up_id := "kit_%s_up@%s" % [strong_k, s.id]
			var plain: Dictionary = kits[s.kits[0]]
			var strong: Dictionary = kits[strong_k]
			var diff := _entry(up_id, strong_k, strong, share)
			diff["name"] = "Reinforce"
			diff["blurb"] = "Sheet metal and doubled planks over the fence that stands."
			diff["scrap"] = maxi(1, roundi((float(strong.get("scrap", 0)) - float(plain.get("scrap", 0))) * share))
			diff["work"] = maxf(1.0, snappedf((float(strong.get("work", 1.0)) - float(plain.get("work", 0.0))) * share, 0.5))
			diff["upgrade_of"] = plain_id
			buildings.append(diff)
			kit_buildings.append(up_id)
		plots.append({
			"id": String(s.id), "name": String(s.name), "kind": "slot", "lot": "", "home": "", "n": 1, "why": _why(s),
			"pos": _pt(_center_of(r)), "size": [float(r.size.x), float(r.size.y)], "work": _pt(Vector2(s.work)),
			"kits": kit_buildings, "dir": String(s.dir), "side": String(s.side), "unlock": s.unlock.duplicate(),
		})

	var spawn_info := _spawns(town, grid, _center_of(rect), opts, table)
	return {
		"version": VERSION, "house": house_id, "kind": String(h.kind), "front": front,
		"plot": lot, "center": _center_of(rect), "yard_middle": yard_middle, "compound": Rect2(lot).grow(_num(knobs, "ring", 3.0)),
		"claim_spot": claim_spot, "interior": interior, "stations": stations, "rest": rest, "posts": posts, "doors": doors,
		"slots": slots, "plots": plots, "buildings": buildings, "spawns": spawn_info.spawns, "spawn_range": spawn_info.range,
		"ring": {"free": ring_free, "blocked": ring_tiles - ring_free},
		"inner": Rect2i(xl, yt, xr - xl + 1, yb - yt + 1), "gate": gate_id, "kits": kits,
	}


# ---------------------------------------------------------------- the slots --

static func _toward(o: Vector2i) -> String:
	# the dead stand outside and face the wall: they look the way opposite to the outward step
	if o.y > 0:
		return "N"
	if o.y < 0:
		return "S"
	return "W" if o.x > 0 else "E"


static func _slot(id: String, kind: String, nm: String, r: Rect2i, dir: String, side: String, role: String, kit_ids: Array, places: Array, kits: Dictionary, unlock: Dictionary, work: Vector2, grid: Grid, door: String = "") -> Dictionary:
	var ok_kits: Array = []
	for k in kit_ids:
		if kits.has(k):
			ok_kits.append(k)
	var tiles: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			tiles.append(y * grid.w + x)
	return {"id": id, "kind": kind, "name": nm, "rect": r, "dir": dir, "side": side, "role": role, "unlock": {"crew": int(unlock.get(role, 1))},
		"kits": ok_kits, "dead_places": places, "post": "", "center": _center_of(r), "work": work, "door": door, "tiles": tiles}


## The catalogue entry of a kit on a slot: the kit's numbers times `share` (a fence section's length over the kit's `per_tiles`; 1 for the rest), hit points to the nearest 5.
static func _entry(id: String, kit_id: String, kd: Dictionary, share: float) -> Dictionary:
	return {
		"id": id, "name": String(kd.get("name", kit_id)), "blurb": String(kd.get("blurb", "")), "scrap": maxi(1, roundi(float(kd.get("scrap", 0)) * share)),
		"work": maxf(1.0, snappedf(float(kd.get("work", 1.0)) * share, 0.5)), "max": 99, "requires": "", "effects": kd.get("effects", {}).duplicate(), "slot_kit": kit_id,
		"hp": snappedf(float(kd.get("hp", 0.0)) * share, 5.0), "bonus": bool(kd.get("bonus", false)),
	}


static func _take(taken: Dictionary, grid: Grid, r: Rect2i, id: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			taken[y * grid.w + x] = id


## The runs of free tiles along a row (`horizontal`: from `a` to `b` at y == `line`) or a column (at x == `line`): arrays of the coordinate along it.
static func _free_run(grid: Grid, a: int, b: int, line: int, horizontal: bool) -> Array:
	var runs: Array = []
	var cur: Array = []
	for i in range(a, b + 1):
		var ok := grid.open(i, line) if horizontal else grid.open(line, i)
		if ok:
			cur.append(i)
		elif not cur.is_empty():
			runs.append(cur)
			cur = []
	if not cur.is_empty():
		runs.append(cur)
	return runs


## `n` tiles in sections of at most `most`, as evenly as can be (7 in fives is 4 and 3).
static func _chunks(n: int, most: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var k := ceili(float(n) / float(maxi(most, 1)))
	@warning_ignore("integer_division")
	var base := n / k
	var extra := n % k
	for i in k:
		out.append(base + (1 if i < extra else 0))
	return out


## The places the dead stand to claw a section: one for each tile along it, just outside the outer face (`outward` -1 or 1 along the other axis),
## with the approach point a little further out (the place itself where that is not open ground); a tile whose outside is shut (a car, a neighbour's
## wall) tries one tile further out, and gives no place when that is shut too.
static func _places(grid: Grid, r: Rect2i, dir: String, outward: int, stand: float) -> Array:
	var out: Array = []
	var o := float(outward)
	if dir == "h":
		var face := float(r.position.y) + (1.0 if outward > 0 else 0.0)
		for x in range(r.position.x, r.end.x):
			var px := float(x) + 0.5
			for extra: float in [0.0, 1.0]:
				var py: float = face + o * (stand + extra)
				if grid.open_f(px, py):
					var ay: float = py + o * 1.2
					out.append({"x": px, "y": py, "ax": px, "ay": ay if grid.open_f(px, ay) else py, "face": "N" if outward > 0 else "S"})
					break
	else:
		var face := float(r.position.x) + (1.0 if outward > 0 else 0.0)
		for y in range(r.position.y, r.end.y):
			var py := float(y) + 0.5
			for extra: float in [0.0, 1.0]:
				var px: float = face + o * (stand + extra)
				if grid.open_f(px, py):
					var ax: float = px + o * 1.2
					out.append({"x": px, "y": py, "ax": ax if grid.open_f(ax, py) else px, "ay": py, "face": "W" if outward > 0 else "E"})
					break
	return out


## The tile itself if it is open ground, else the nearest open one inside `within` (the house) up to three tiles away; the tile when there is none.
static func _nearest_open(grid: Grid, t: Vector2i, within: Rect2i) -> Vector2i:
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := Vector2i(t.x + dx, t.y + dy)
				if grid.open(c.x, c.y) and within.has_point(c):
					return c
	return t


## The nearest free tile to `t` (itself first) within two tiles that is not reserved, not taken by a slot, in the yard's inner ring's rectangle and not in the
## house; (-1, -1) when none.
static func _free_near(grid: Grid, t: Vector2i, reserved: Dictionary, taken: Dictionary, inner: Rect2i, house: Rect2i) -> Vector2i:
	for r in range(0, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := Vector2i(t.x + dx, t.y + dy)
				if grid.open(c.x, c.y) and not reserved.has(c) and not taken.has(c.y * grid.w + c.x) and inner.has_point(c) and not house.has_point(c):
					return c
	return Vector2i(-1, -1)


static func _why(s: Dictionary) -> String:
	match String(s.kind):
		"gate":
			return "In front of the front door: people pass whole, the dead do not."
		"door":
			return "Planks across the barred %s." % String(s.name).to_lower()
		"tower":
			return "A lookout and a firing platform in the corner of the yard."
		"floodlight":
			return "A lamp on a pole at the side of the yard."
	return "A stretch of the fence along the %s side of the lot." % String(COMPASS.get(String(s.side), "")).to_lower()


# ----------------------------------------------------------------- the posts --

## The tiles of the inner ring, clockwise from its top left corner.
static func _ring(xl: int, xr: int, yt: int, yb: int) -> Array:
	var out: Array = []
	for x in range(xl, xr + 1):
		out.append(Vector2i(x, yt))
	for y in range(yt + 1, yb + 1):
		out.append(Vector2i(xr, y))
	for x in range(xr - 1, xl - 1, -1):
		out.append(Vector2i(x, yb))
	for y in range(yb - 1, yt, -1):
		out.append(Vector2i(xl, y))
	return out


## Which side of the lot's ring a tile of the inner ring is on ("N" for the top row, "S" the bottom, "W", "E"): the way a post faces.
static func _side_of_tile(t: Vector2i, lx: int, ly: int, lw: int, lh: int) -> String:
	if t.y == ly + 1:
		return "N"
	if t.y == ly + lh - 2:
		return "S"
	return "W" if t.x == lx + 1 else "E"


static func _compass_of_tile(t: Vector2i, lx: int, ly: int, lw: int, lh: int, _full: bool) -> String:
	return String(COMPASS[_side_of_tile(t, lx, ly, lw, lh)])


static func _post(t: Vector2i, what: String, slot: String, lx: int, ly: int, lw: int, lh: int) -> Dictionary:
	return {"id": "", "name": "", "pos": [float(t.x) + 0.5, float(t.y) + 0.5], "what": what, "face": _side_of_tile(t, lx, ly, lw, lh), "slot": slot}


## The slot on the border tile just outside an inner ring tile ("" when there is none).
static func _slot_at_border(taken: Dictionary, grid: Grid, t: Vector2i, lx: int, ly: int, lw: int, lh: int) -> String:
	var side := _side_of_tile(t, lx, ly, lw, lh)
	var b := t
	match side:
		"N":
			b = Vector2i(t.x, ly)
		"S":
			b = Vector2i(t.x, ly + lh - 1)
		"W":
			b = Vector2i(lx, t.y)
		_:
			b = Vector2i(lx + lw - 1, t.y)
	return String(taken.get(b.y * grid.w + b.x, ""))


# ------------------------------------------------------------- the interior --

## The room (an index) a prop goes in: the first room of the house with one of the names the prop likes that has a free tile, else the roomiest with one.
static func _room_for(town: Dictionary, h: Dictionary, pid: String, grid: Grid, avoid: Dictionary, used: Dictionary, wide: int, front := false) -> int:
	var rooms: Array = h.rooms
	for want in PROP_ROOMS[pid]:
		for ri in rooms:
			if String(town.rooms[ri].name) == String(want) and _spare(grid, town.rooms[ri].rect, avoid, used, wide, front).x >= 0:
				return int(ri)
	var best := -1
	var best_area := -1
	for ri in rooms:
		var r: Rect2i = town.rooms[ri].rect
		if r.size.x * r.size.y > best_area and _spare(grid, r, avoid, used, wide, front).x >= 0:
			best = int(ri)
			best_area = r.size.x * r.size.y
	return best


## Where to stand to work a prop on `tile` (`wide` tiles wide): the first of `n` free tiles in a row, in the row south of it first (the way the people are drawn, facing it), then the row
## north, then beside it. (-1, -1) when there is no room.
static func _stand_for(grid: Grid, doorway: Dictionary, used: Dictionary, tile: Vector2i, wide: int, n: int) -> Vector2i:
	var tries: Array = []
	for dy in [1, -1]:
		for dx in [0, -1, 1]:
			tries.append(Vector2i(tile.x + dx, tile.y + dy))
	tries.append(Vector2i(tile.x - n, tile.y))
	tries.append(Vector2i(tile.x + wide, tile.y))
	for t in tries:
		var ok := true
		for k in n:
			var c := Vector2i(t.x + k, t.y)
			if not grid.open(c.x, c.y) or doorway.has(c) or used.has(c):
				ok = false
		if ok:
			return t
	return Vector2i(-1, -1)


## A free tile of a floor (`wide` tiles in a row), not by a door and not used: the one with the most free neighbours, the first of them in reading order.
## `front`: the tiles just south of it (in the same room) must be free too (a place to stand in front of it).
## `away` (a point, or (-1, -1) for none): of the tiles that fit the one farthest from it wins, the free neighbours only break a tie.
static func _spare(grid: Grid, r: Rect2i, avoid: Dictionary, used: Dictionary, wide: int, front := false, away := Vector2(-1.0, -1.0)) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := -1
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var ok := true
			for k in wide:
				var c := Vector2i(x + k, y)
				if not grid.open(c.x, c.y) or avoid.has(c) or used.has(c) or c.x >= r.end.x:
					ok = false
				if front:
					var f := Vector2i(x + k, y + 1)
					if f.y >= r.end.y or not grid.open(f.x, f.y) or avoid.has(f) or used.has(f):
						ok = false
			if not ok:
				continue
			var n := 0
			for dy in range(-1, 2):
				for dx in range(-1, wide + 1):
					if grid.open(x + dx, y + dy):
						n += 1
			if away.x >= 0.0:
				n += int(Vector2(float(x) + 0.5, float(y) + 1.5).distance_to(away) * 10.0)
			if n > best_n:
				best_n = n
				best = Vector2i(x, y)
	return best


## The stations (stations.json's entries for the base's five, with this base's places) as the jobs module reads them.
static func _stations(grid: Grid, town: Dictionary, h: Dictionary, interior: Array, prop_at: Dictionary, slots: Array, tower_ids: Array, yard_middle: Vector2, front_door: Dictionary, xl: int, xr: int, yt: int, yb: int, used: Dictionary, avoid: Dictionary) -> Array:
	var file := {}
	if FileAccess.file_exists(STATIONS_PATH):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(STATIONS_PATH))
		if raw is Dictionary:
			for st in raw.get("stations", []):
				file[String(st.id)] = st
	var spots := {}
	var seat_offsets := {}
	if prop_at.has("bench"):
		spots["bench"] = [prop_at.bench.get("front", prop_at.bench.pos), "the worktable"]
		if prop_at.bench.has("seat_offsets"):
			seat_offsets["bench"] = prop_at.bench.seat_offsets
	if prop_at.has("radio"):
		spots["radio"] = [prop_at.radio.get("front", prop_at.radio.pos), "the radio"]
	# the lookout stands where the first tower's post is, else at the first tower's tile, else by the front gate
	var watch_at := yard_middle
	for s in slots:
		if String(s.kind) == "tower":
			watch_at = Vector2(s.work)
			break
	spots["watch"] = [watch_at, "the tower"]
	# the builders: the front yard, a row of three free tiles (the seats are a tile and a tenth to either side), a row out from the door
	var yard_spot := yard_middle
	var step := 1 if (front_door.is_empty() or int(front_door.out.y) >= int(front_door["in"].y)) else -1
	var found := false
	for k in [1, 2, 0]:
		for dx in [0, 1, -1, 2, -2, 3, -3]:
			var c := Vector2i(floori(yard_middle.x) + dx, floori(yard_middle.y) + k * step)
			if not found and grid.open(c.x - 1, c.y) and grid.open(c.x, c.y) and grid.open(c.x + 1, c.y):
				yard_spot = _tile_center(c)
				found = true
	spots["builders"] = [yard_spot, "the yard"]
	# the infirmary: a free pair of tiles in a bedroom that is not the bed's if the house has another, else in the bed's room, else the roomiest free floor
	var inf_at := yard_middle
	var bed_room: int = int(prop_at.bed.room) if prop_at.has("bed") else (int(h.rooms[0]) if not h.rooms.is_empty() else -1)
	var pair := Vector2i(-1, -1)
	for ri in h.rooms:
		if pair.x < 0 and int(ri) != bed_room and String(town.rooms[ri].name) == "bedroom":
			pair = _spare(grid, town.rooms[ri].rect, avoid, used, 2)
	if pair.x < 0 and bed_room >= 0:
		pair = _spare(grid, town.rooms[bed_room].rect, avoid, used, 2)
	if pair.x < 0:
		for ri in h.rooms:
			pair = _spare(grid, town.rooms[ri].rect, avoid, used, 2)
			if pair.x >= 0:
				break
	if pair.x >= 0:
		inf_at = _tile_center(pair)
		used[pair] = true
		used[Vector2i(pair.x + 1, pair.y)] = true
	spots["infirmary"] = [inf_at, "the sickbed"]
	var out: Array = []
	for id in STATIONS:
		var st: Dictionary = file.get(id, {"id": id, "name": id.capitalize(), "seats": 1, "skill": "", "icon": "post", "blurb": "", "what": "At work", "work": id, "settings": {}}).duplicate(true)
		st.erase("requires")
		var spot: Array = spots.get(id, [yard_middle, "the yard"])
		st["pos"] = _pt(Vector2(spot[0]))
		st["where"] = String(spot[1])
		if TOWN_BLURBS.has(id):
			st["blurb"] = String(TOWN_BLURBS[id])
		if seat_offsets.has(id):
			st["seat_offsets"] = [_pt(seat_offsets[id][0]), _pt(seat_offsets[id][1])]
		if st.has("idle_pos"):
			st["idle_pos"] = _pt(yard_spot)
			st["idle_where"] = "the front yard"
		out.append(st)
	return out


## Where the people with no job rest by day: free tiles of the front yard and the inner ring (the words of stations.json's `rest`).
## `night`: where everyone turns in on a quiet night (no attack is on): free floor tiles of the house's rooms (the bedroom's first), not a doorway, a prop or a seat.
static func _rest(grid: Grid, yard_middle: Vector2, front_door: Dictionary, xl: int, xr: int, yt: int, yb: int, posts: Array, town: Dictionary = {}, h: Dictionary = {}, avoid: Dictionary = {}, used: Dictionary = {}) -> Dictionary:
	var out := {"what": "Resting", "work": "rest", "spots": [], "night": []}
	if FileAccess.file_exists(STATIONS_PATH):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(STATIONS_PATH))
		if raw is Dictionary and raw.get("rest") is Dictionary:
			out.what = String(raw.rest.get("what", "Resting"))
			out.work = String(raw.rest.get("work", "rest"))
	var post_tiles := {}
	for po in posts:
		post_tiles[Vector2i(floori(float(po.pos[0])), floori(float(po.pos[1])))] = true
	var out_t := Vector2i(floori(yard_middle.x), floori(yard_middle.y))
	var step := 1 if (front_door.is_empty() or int(front_door.out.y) >= int(front_door["in"].y)) else -1
	# the tiles beside the front door's way and a row further out, as many as are free
	for dy in range(0, 3):
		for dx in [-3, -2, 2, 3, 4, -4]:
			var c := Vector2i(out_t.x + dx, out_t.y + dy * step)
			if out["spots"].size() >= 5:
				break
			if c.x < xl or c.x > xr or c.y < yt or c.y > yb or post_tiles.has(c) or not grid.open(c.x, c.y):
				continue
			out["spots"].append({"pos": _pt(_tile_center(c)), "face": "S" if step > 0 else "N"})
	if not h.is_empty() and town.has("rooms"):
		# (nobody turns in in the bathroom or the hall: they are used only when the rest of the house has fewer than three places)
		var order := ["bedroom", "living room", "front room", "shop floor", "study", "dining room", "kitchen", "storeroom", "utility", "nursery"]
		var rooms: Array = []
		for ri in h.rooms:
			if not ["bathroom", "hall"].has(String(town.rooms[ri].name)):
				rooms.append(ri)
		rooms.sort_custom(func(a, b): return (order.find(String(town.rooms[a].name)) if order.has(String(town.rooms[a].name)) else 9) < (order.find(String(town.rooms[b].name)) if order.has(String(town.rooms[b].name)) else 9))
		var taken := {}
		for pass_n in 3:
			if pass_n == 2:
				if out["night"].size() >= 3:
					break
				for ri in h.rooms:
					if ["bathroom", "hall"].has(String(town.rooms[ri].name)):
						rooms.append(ri)
			for ri in rooms:
				var r: Rect2i = town.rooms[ri].rect
				var best := Vector2i(-1, -1)
				var best_n := -1
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						var c := Vector2i(x, y)
						if not grid.open(x, y) or avoid.has(c) or used.has(c) or taken.has(c):
							continue
						var n := 0
						var crowded := false
						for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var q: Vector2i = c + dv
							if grid.open(q.x, q.y):
								n += 1
							if taken.has(q):
								crowded = true
						if crowded and pass_n == 0:
							continue    # (the first round puts nobody shoulder to shoulder)
						if n > best_n:
							best_n = n
							best = c
				if best.x >= 0 and out["night"].size() < 6:
					taken[best] = true
					out["night"].append({"pos": _pt(_tile_center(best)), "face": "S"})
	return out


# ---------------------------------------------------------------- the spawns --

## The night's entrances: one road tile on each side of the base (north, east, south, west), 35 to 60 tiles from its middle when the town has them
## (the range is widened a step at a time for a small town), each the nearest to the middle of the range with open ground all round it.
static func _spawns(town: Dictionary, grid: Grid, center: Vector2, opts: Dictionary, table: Dictionary) -> Dictionary:
	var knobs: Dictionary = table.get("layout", {})
	var want: Array = opts.get("spawn_range", knobs.get("spawn_range", [35, 60]))
	var asphalt := int(town.data.terrainTypes.ASPHALT.id)
	var terrain: Array = town.data.terrain
	var levels := [[float(want[0]), float(want[1])], [24.0, 72.0], [14.0, 90.0], [4.0, 140.0]]
	var best_sides := {}
	var used_range: Array = levels[0]
	for lv in levels:
		var lo: float = lv[0]
		var hi: float = lv[1]
		var target := (lo + hi) * 0.5
		var best := {"N": [INF, Vector2.ZERO], "E": [INF, Vector2.ZERO], "S": [INF, Vector2.ZERO], "W": [INF, Vector2.ZERO]}
		var x0 := maxi(1, floori(center.x - hi))
		var x1 := mini(grid.w - 2, ceili(center.x + hi))
		var y0 := maxi(1, floori(center.y - hi))
		var y1 := mini(grid.h - 2, ceili(center.y + hi))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if int(terrain[y * grid.w + x]) != asphalt or not grid.open(x, y):
					continue
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				var d := p.distance_to(center)
				if d < lo or d > hi:
					continue
				var clear := true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if not grid.open(x + dx, y + dy):
							clear = false
				if not clear:
					continue
				var dv := p - center
				var side := ("E" if dv.x > 0.0 else "W") if absf(dv.x) > absf(dv.y) else ("S" if dv.y > 0.0 else "N")
				var score := absf(d - target)
				if score < float(best[side][0]):
					best[side] = [score, p]
		var missing := 0
		for s in best:
			if float(best[s][0]) == INF:
				missing += 1
		if missing == 0 or lv == levels[levels.size() - 1]:
			best_sides = best
			used_range = lv
			break
	var out: Array = []
	var fallback := Vector2.ZERO
	for s in ["N", "E", "S", "W"]:
		if float(best_sides[s][0]) < INF:
			fallback = best_sides[s][1]
	for s in ["N", "E", "S", "W"]:
		out.append(best_sides[s][1] if float(best_sides[s][0]) < INF else fallback)
	return {"spawns": out, "range": [float(used_range[0]), float(used_range[1])]}


# ------------------------------------------------------------------ validate --

## The problems of a layout against its town (empty is good): slots on free tiles and not overlapping, a gate on the front, the kits known and fitting
## their slots, the unlock stages, the dead's places on open ground, at least `posts_min` posts inside the perimeter on free tiles, the stations, the
## props, the plots and buildings that go with the slots, the spawns on walkable ground in their range, and a way for people from the claim spot to
## every post, station, work spot and resting spot.
static func validate(layout: Dictionary, town: Dictionary) -> Array:
	var bad: Array = []
	var grid := _grid(town)
	var table := load_kits()
	var knobs: Dictionary = table.get("layout", {})
	var kits: Dictionary = layout.get("kits", {})
	if int(layout.get("version", 0)) != VERSION:
		bad.append("version")
	var h: Dictionary = town.houses[int(layout.get("house", -1))] if int(layout.get("house", -1)) >= 0 and int(layout.get("house", -1)) < town.houses.size() else {}
	if h.is_empty():
		bad.append("no such house")
		return bad
	var plot: Rect2i = layout.plot
	if plot != Rect2i(h.lot):
		bad.append("plot is not the house's lot")
	if String(layout.front) != String(h.front):
		bad.append("front is not the house's")
	if kits.is_empty():
		bad.append("no kits")
	var tiles_seen := {}
	var ids := {}
	var gates := 0
	var side_places := {}
	var inner: Rect2i = layout.get("inner", Rect2i())
	for s in layout.slots:
		var id := String(s.id)
		if ids.has(id):
			bad.append("slot id twice: " + id)
		ids[id] = s
		if not SLOT_KINDS.has(String(s.kind)):
			bad.append("slot kind unknown: " + id)
		var r: Rect2i = s.rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if not grid.open(x, y):
					bad.append("slot tile not free: %s at %d,%d" % [id, x, y])
				var key := y * grid.w + x
				if tiles_seen.has(key):
					bad.append("slots overlap: %s and %s" % [id, tiles_seen[key]])
				tiles_seen[key] = id
		var on_border := not Rect2i(plot.position + Vector2i(1, 1), plot.size - Vector2i(2, 2)).encloses(r)
		match String(s.kind):
			"fence", "gate":
				if not on_border or not plot.encloses(r):
					bad.append("%s is not on the lot's border" % id)
			"door":
				if not Rect2i(h.rect).encloses(r):
					bad.append("%s is not in the house's wall" % id)
			_:
				if on_border or not plot.encloses(r):
					bad.append("%s is not inside the perimeter" % id)
		if String(s.kind) == "gate":
			gates += 1
			var front_row: int = plot.end.y - 1 if String(layout.front) == "S" else plot.position.y
			if r.position.y != front_row or r.size.y != 1:
				bad.append("the gate is not on the front")
		if s.kits.is_empty():
			bad.append("slot has no kit: " + id)
		for k in s.kits:
			if not kits.has(k):
				bad.append("kit unknown: %s on %s" % [k, id])
			elif not Array(kits[k].get("slot_kinds", [])).has(String(s.kind)):
				bad.append("kit %s does not fit %s" % [k, id])
		var crew := int(s.unlock.get("crew", 0))
		if crew < 1 or crew > 4:
			bad.append("unlock stage out of range: " + id)
		if project_of(String(s.get("role", "")), table) == "":
			bad.append("slot in no project: " + id)
		if String(s.kind) in ["gate", "door"] and Array(s.dead_places).is_empty():
			bad.append("no place for the dead at " + id)
		if String(s.kind) == "fence":
			side_places[String(s.side)] = int(side_places.get(String(s.side), 0)) + Array(s.dead_places).size()
		for pl in s.dead_places:
			if not grid.open_f(float(pl.x), float(pl.y)) or not grid.open_f(float(pl.ax), float(pl.ay)):
				bad.append("a dead one's place is not open ground at " + id)
			if plot.has_point(Vector2i(floori(float(pl.x)), floori(float(pl.y)))) and String(s.kind) != "door":
				bad.append("a dead one's place is inside the lot at " + id)
	for sd in side_places:
		if int(side_places[sd]) <= 0:
			bad.append("no place for the dead along the %s fence" % String(sd))
	if gates != 1:
		bad.append("the base needs exactly one gate (has %d)" % gates)
	if int(layout.get("ring", {}).get("free", 0)) + int(layout.get("ring", {}).get("blocked", 0)) <= 0:
		bad.append("no ring report")
	# doors
	if layout.doors.is_empty():
		bad.append("no doors to bar")
	for d in layout.doors:
		for t in d.tiles:
			if not Rect2i(h.rect).has_point(Vector2i(t)):
				bad.append("door tile outside the house")
		if not ids.has(String(d.slot)):
			bad.append("a door has no slot")
	# posts
	var min_posts := int(_num(knobs, "posts_min", 8.0))
	if layout.posts.size() < min_posts:
		bad.append("only %d posts" % layout.posts.size())
	var post_ids := {}
	var post_tiles := {}
	for po in layout.posts:
		var t := Vector2i(floori(float(po.pos[0])), floori(float(po.pos[1])))
		if post_ids.has(String(po.id)):
			bad.append("post id twice")
		post_ids[String(po.id)] = true
		if post_tiles.has(t):
			bad.append("two posts on a tile")
		post_tiles[t] = true
		if not grid.open(t.x, t.y):
			bad.append("post not on a free tile: " + String(po.id))
		if not plot.has_point(t) or not Rect2i(plot.position + Vector2i(1, 1), plot.size - Vector2i(2, 2)).has_point(t):
			bad.append("post not inside the perimeter: " + String(po.id))
		if String(po.slot) != "" and not ids.has(String(po.slot)):
			bad.append("post names an unknown slot")
		if not String(po.face) in ["N", "E", "S", "W"]:
			bad.append("post has no face")
	for s in layout.slots:
		if String(s.post) != "" and not post_ids.has(String(s.post)):
			bad.append("slot names an unknown post: " + String(s.id))
	# interior, stations, rest
	var props := {}
	for p in layout.interior:
		props[String(p.id)] = p
		var pt := Vector2i(floori(float(p.pos.x)), floori(float(p.pos.y)))
		if not Rect2i(h.rect).has_point(pt) or not grid.open(pt.x, pt.y):
			bad.append("prop not on a free tile in the house: " + String(p.id))
	for pid in PROPS:
		if not props.has(pid):
			bad.append("prop missing: " + pid)
	var have := {}
	for st in layout.stations:
		have[String(st.id)] = st
		var p := Vector2i(floori(float(st.pos[0])), floori(float(st.pos[1])))
		if not grid.open(p.x, p.y):
			bad.append("station not on a free tile: " + String(st.id))
	for sid in STATIONS:
		if not have.has(sid):
			bad.append("station missing: " + sid)
	if layout.rest.spots.is_empty():
		bad.append("no resting spots")
	# plots and buildings
	var plot_ids := {}
	for pl in layout.plots:
		plot_ids[String(pl.id)] = pl
		if not ids.has(String(pl.id)):
			bad.append("plot without a slot: " + String(pl.id))
		if String(pl.kind) != "slot" or String(pl.home) != "":
			bad.append("plot is not a slot plot: " + String(pl.id))
	for id in ids:
		if not plot_ids.has(id):
			bad.append("slot without a plot: " + String(id))
	var building_ids := {}
	for b in layout.buildings:
		building_ids[String(b.id)] = b
	for pl in layout.plots:
		for k in pl.kits:
			if not building_ids.has(String(k)):
				bad.append("plot kit has no catalogue entry: " + String(k))
	# spawns
	var center: Vector2 = layout.center
	var sr: Array = layout.get("spawn_range", [0.0, 0.0])
	if layout.spawns.size() != int(_num(knobs, "spawn_count", 4.0)):
		bad.append("spawn count")
	for sp in layout.spawns:
		var d := Vector2(sp).distance_to(center)
		if not grid.open_f(sp.x, sp.y):
			bad.append("spawn not on walkable ground")
		if d < float(sr[0]) - 0.01 or d > float(sr[1]) + 0.01:
			bad.append("spawn outside its range")
	if int(town.data.W) >= 160 and float(sr[0]) < 35.0:
		bad.append("a big town has spawns 35 tiles out")
	# the way: from the claim spot to every post, work spot, station, resting spot and dead place of a door
	var comp: Rect2 = layout.compound
	var reach := _flood(grid, Vector2i(floori(layout.claim_spot.x), floori(layout.claim_spot.y)), comp)
	var wants: Array = []
	for po in layout.posts:
		wants.append(["post " + String(po.id), Vector2(float(po.pos[0]), float(po.pos[1]))])
	for st in layout.stations:
		wants.append(["station " + String(st.id), Vector2(float(st.pos[0]), float(st.pos[1]))])
	for sp in layout.rest.spots:
		wants.append(["rest spot", Vector2(float(sp.pos[0]), float(sp.pos[1]))])
	for s in layout.slots:
		wants.append(["work spot of " + String(s.id), Vector2(s.work)])
	for w in wants:
		var v: Vector2 = w[1]
		if not reach.has(Vector2i(floori(v.x), floori(v.y))):
			bad.append("no way for people to %s" % String(w[0]))
	return bad


## The tiles people can walk to from `from` without leaving `bounds` (a flood on the people's grid).
static func _flood(grid: Grid, from: Vector2i, bounds: Rect2) -> Dictionary:
	var seen := {}
	if not grid.open(from.x, from.y):
		return seen
	var stack: Array = [from]
	seen[from] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dv
			if seen.has(n) or not bounds.has_point(Vector2(float(n.x) + 0.5, float(n.y) + 0.5)) or not grid.open(n.x, n.y):
				continue
			seen[n] = true
			stack.append(n)
	return seen
