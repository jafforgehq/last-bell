## The plans of the town's buildings (One House, TOWNGEN): pure data and dice, no canvas. `plan(kind, ...)` draws the sizes and the parts of a building of a kind for a row of lots
## (the lot layout, scripts/town/town_layout.gd, asks it to know how wide a lot must be); `programs(kind)` gives the rooms of each part. scripts/town/building_gen.gd paints them.
##
## A PLAN is {"kind", "box": Vector2i (the footprint's bounding box), "parts": [Rect2i] (rectangles of outer walls in the box, the FRONT at y = 0; parts touch along a wall they share),
## "margin": the yard to the sides of it, "fy": the front yard's depth, "landmark": ""|"bell_tower", "garage": 1 when a part is a garage}.
extends RefCounted


static func _r(rng: RandomNumberGenerator, pair: Array) -> int:
	return rng.randi_range(int(pair[0]), int(pair[1]))


static func _rect_plan(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator, wr: Array, hr: Array, mr: Array, fyr: Array) -> Dictionary:
	var fy := _r(rng, fyr)
	var hmax := mini(int(hr[1]), depth - fy - 1)
	if hmax < int(hr[0]):
		fy = int(fyr[0])
		hmax = mini(int(hr[1]), depth - fy - 1)
		if hmax < int(hr[0]):
			return {}
	var h := rng.randi_range(int(hr[0]), hmax)
	var w := _r(rng, wr)
	if w > avail_w:
		w = avail_w
	if w < int(wr[0]):
		return {}
	return {"kind": kind, "box": Vector2i(w, h), "parts": [Rect2i(0, 0, w, h)], "margin": _r(rng, mr), "fy": fy}


## The plan of a building of `kind` that fits `avail_w` tiles of a row and `depth` of its depth, or {} when it does not fit. BIGGER HOUSES: "start" is the start house, a FAMILY HOME of
## 18 x 14 (eight rooms round a central hall) in a lot of 24 x 21 with three tiles to spare on every side; "family" is the same kind of home at 16 to 19 x 13 to 14; the detached houses
## ("medium", "small", the bungalow with its garage, the L, T, U and two wing houses) are 11 to 14 wide and 9 to 10 deep and up; the "cottage" is the one tiny house left (a few percent of
## the town) and is never a rescue house or the start.
static func plan(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	match kind:
		"start":
			if avail_w < 22 or depth < 20:
				return {}
			# (three tiles of ground to each side and four in front where the block has the room, two and three where it has not)
			return {"kind": kind, "box": Vector2i(18, 14), "parts": [Rect2i(0, 0, 18, 14)], "margin": mini(3, (avail_w - 18) / 2), "fy": 4 if depth >= 21 else 3}
		"family":
			return _rect_plan(kind, avail_w, depth, rng, [16, 19], [13, 14], [1, 3], [2, 3])
		"small":
			return _rect_plan(kind, avail_w, depth, rng, [11, 12], [9, 9], [1, 3], [1, 3])
		"medium":
			return _rect_plan(kind, avail_w, depth, rng, [12, 14], [9, 10], [1, 3], [1, 3])
		"terrace":
			return _rect_plan(kind, avail_w, depth, rng, [7, 7], [9, 11], [0, 0], [1, 2])
		"cottage":
			return _rect_plan(kind, avail_w, depth, rng, [7, 7], [6, 7], [1, 2], [1, 3])
		"rowshop":
			return _rect_plan(kind, avail_w, depth, rng, [8, 10], [9, 11], [0, 0], [1, 2])
		"shed":
			return {"kind": kind, "box": Vector2i(7, 5), "parts": [Rect2i(0, 0, 7, 5)], "margin": 0, "fy": 0}
		"shed_lot":
			# a shed standing in a lot of its own (a pocket of the suburb filled in): two small rooms
			return _rect_plan("shed", avail_w, depth, rng, [7, 7], [5, 5], [0, 2], [1, 2])
		"kiosk":
			return _rect_plan(kind, avail_w, depth, rng, [7, 8], [5, 6], [0, 1], [1, 1])
		"cornershop":
			return _rect_plan(kind, avail_w, depth, rng, [10, 12], [9, 11], [0, 1], [1, 2])
		"shop":
			return _rect_plan(kind, avail_w, depth, rng, [11, 14], [9, 12], [0, 2], [1, 2])
		"pharmacy":
			return _rect_plan(kind, avail_w, depth, rng, [11, 13], [9, 11], [0, 1], [1, 2])
		"bakery":
			return _rect_plan(kind, avail_w, depth, rng, [10, 12], [9, 11], [0, 1], [1, 2])
		"hardware":
			return _rect_plan(kind, avail_w, depth, rng, [12, 15], [10, 12], [0, 2], [1, 2])
		"diner":
			return _rect_plan(kind, avail_w, depth, rng, [13, 16], [9, 11], [0, 2], [1, 2])
		"bank":
			return _rect_plan(kind, avail_w, depth, rng, [11, 13], [9, 11], [0, 1], [1, 2])
		"office":
			return _rect_plan(kind, avail_w, depth, rng, [11, 14], [9, 12], [0, 2], [1, 2])
		"apartments":
			return _rect_plan(kind, avail_w, depth, rng, [18, 22], [12, 14], [0, 2], [1, 2])
		"supermarket":
			return _rect_plan(kind, avail_w, depth, rng, [16, 19], [10, 11], [3, 6], [7, 8])
		"library":
			return _rect_plan(kind, avail_w, depth, rng, [12, 14], [9, 10], [2, 4], [2, 3])
		"clinic":
			return _rect_plan(kind, avail_w, depth, rng, [14, 16], [10, 11], [2, 4], [2, 3])
		"fire_station":
			return _rect_plan(kind, avail_w, depth, rng, [14, 16], [10, 11], [2, 4], [3, 4])
		"police":
			return _rect_plan(kind, avail_w, depth, rng, [12, 14], [9, 10], [2, 4], [2, 3])
		"warehouse":
			return _rect_plan(kind, avail_w, depth, rng, [17, 22], [11, 13], [2, 4], [2, 4])
		"garage":
			return _rect_plan(kind, avail_w, depth, rng, [12, 14], [9, 10], [2, 4], [3, 4])
		"workshop":
			return _rect_plan(kind, avail_w, depth, rng, [10, 12], [8, 9], [2, 4], [2, 4])
		"barn":
			return _rect_plan(kind, avail_w, depth, rng, [11, 13], [7, 8], [2, 4], [2, 3])
		"scrapyard":
			return _rect_plan(kind, avail_w, depth, rng, [7, 8], [5, 6], [14, 18], [1, 2]) if avail_w >= 18 and depth >= 12 else {}
		"containers":
			return _rect_plan(kind, avail_w, depth, rng, [7, 7], [5, 5], [14, 18], [1, 2]) if avail_w >= 18 and depth >= 12 else {}
		"farmhouse":
			# (a farm lot is a strip of ten: the house is a long one of eight deep, three rooms side by side; where a lot is deeper an L)
			if depth >= 15 and rng.randf() < 0.5:
				var l := _plan_l(kind, avail_w, depth, rng, [12, 14], [7, 8], [8, 9], [7, 8], [2, 4], [1, 2])
				if not l.is_empty():
					return l
			return _rect_plan(kind, avail_w, depth, rng, [13, 15], [7, 8], [2, 4], [1, 2])
		"lhouse":
			return _plan_l(kind, avail_w, depth, rng, [14, 16], [8, 8], [9, 10], [8, 9], [2, 4], [1, 3])
		"thouse":
			return _plan_t(kind, avail_w, depth, rng)
		"uhouse":
			return _plan_u(kind, avail_w, depth, rng)
		"twowing":
			return _plan_two(kind, avail_w, depth, rng)
		"bungalow":
			return _plan_bungalow(kind, avail_w, depth, rng)
		"terrace_ext":
			return _plan_terrace_ext(kind, avail_w, depth, rng)
		"church":
			return _plan_church(kind, avail_w, depth, rng)
		"school":
			return _plan_school(kind, avail_w, depth, rng)
	return {}


static func _plan_l(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator, w1r: Array, h1r: Array, w2r: Array, h2r: Array, mr: Array, fyr: Array) -> Dictionary:
	var w1 := _r(rng, w1r)
	var h1 := _r(rng, h1r)
	var w2 := _r(rng, w2r)
	var h2 := _r(rng, h2r)
	var fy := _r(rng, fyr)
	if w1 > avail_w:
		w1 = avail_w
	if w1 < int(w1r[0]):
		return {}
	w2 = mini(w2, w1 - 3)
	while h1 + h2 - 1 + fy + 1 > depth:
		if h2 > int(h2r[0]):
			h2 -= 1
		elif h1 > int(h1r[0]):
			h1 -= 1
		elif fy > int(fyr[0]):
			fy -= 1
		else:
			return {}
	var xw := 0 if rng.randf() < 0.5 else w1 - w2
	return {"kind": kind, "box": Vector2i(w1, h1 + h2 - 1), "parts": [Rect2i(0, 0, w1, h1), Rect2i(xw, h1 - 1, w2, h2)], "margin": _r(rng, mr), "fy": fy}


static func _plan_t(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var w1 := _r(rng, [16, 18])
	var h1 := _r(rng, [7, 8])
	var w2 := _r(rng, [8, 9])
	var h2 := _r(rng, [7, 8])
	var fy := _r(rng, [1, 3])
	if w1 > avail_w:
		w1 = avail_w
	if w1 < 16:
		return {}
	while h1 + h2 - 1 + fy + 1 > depth:
		if h2 > 7:
			h2 -= 1
		elif h1 > 7:
			h1 -= 1
		elif fy > 1:
			fy -= 1
		else:
			return {}
	var xs := clampi((w1 - w2) / 2 + rng.randi_range(-1, 1), 1, w1 - w2 - 1)
	return {"kind": kind, "box": Vector2i(w1, h1 + h2 - 1), "parts": [Rect2i(0, 0, w1, h1), Rect2i(xs, h1 - 1, w2, h2)], "margin": _r(rng, [2, 4]), "fy": fy}


static func _plan_u(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var w := _r(rng, [18, 20])
	var h := _r(rng, [13, 14])
	var fy := _r(rng, [1, 2])
	if w > avail_w:
		w = avail_w
	if w < 18 or h + fy + 2 > depth:
		return {}
	var hb := 7
	var ws := 6
	return {"kind": kind, "box": Vector2i(w, h), "parts": [Rect2i(0, h - hb, w, hb), Rect2i(0, 0, ws, h - hb + 1), Rect2i(w - ws, 0, ws, h - hb + 1)], "margin": _r(rng, [2, 3]), "fy": fy}


static func _plan_two(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var w1 := _r(rng, [10, 12])
	var h1 := _r(rng, [8, 9])
	var w2 := _r(rng, [9, 10])
	var h2 := _r(rng, [8, 9])
	var fy := _r(rng, [1, 3])
	if w1 + w2 - 1 > avail_w:
		return {}
	var dy := rng.randi_range(1, maxi(1, h1 - 4))
	while maxi(h1, dy + h2) + fy + 1 > depth:
		if dy > 0:
			dy -= 1
		elif h2 > 8:
			h2 -= 1
		elif fy > 1:
			fy -= 1
		else:
			return {}
	var parts: Array = [Rect2i(0, 0, w1, h1), Rect2i(w1 - 1, dy, w2, h2)]
	if rng.randf() < 0.5:
		parts = [Rect2i(w2 - 1, 0, w1, h1), Rect2i(0, dy, w2, h2)]
	return {"kind": kind, "box": Vector2i(w1 + w2 - 1, maxi(h1, dy + h2)), "parts": parts, "margin": _r(rng, [1, 3]), "fy": fy}


static func _plan_bungalow(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var w1 := _r(rng, [11, 13])
	var h1 := _r(rng, [9, 9])
	var gw := 6
	var gh := 6
	var fy := _r(rng, [1, 3])
	if w1 + gw - 1 > avail_w or h1 + fy + 1 > depth:
		return {}
	var dy := rng.randi_range(0, maxi(0, h1 - gh))
	var parts: Array
	if rng.randf() < 0.5:
		parts = [Rect2i(0, 0, w1, h1), Rect2i(w1 - 1, dy, gw, gh)]
	else:
		parts = [Rect2i(gw - 1, 0, w1, h1), Rect2i(0, dy, gw, gh)]
	return {"kind": kind, "box": Vector2i(w1 + gw - 1, maxi(h1, dy + gh)), "parts": parts, "margin": _r(rng, [1, 3]), "fy": fy, "garage": 1}


static func _plan_terrace_ext(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var w := 7
	var h1 := _r(rng, [8, 9])
	var fy := 1
	if w > avail_w or h1 + 3 + fy + 1 > depth:
		return _rect_plan("terrace", avail_w, depth, rng, [7, 7], [9, 11], [0, 0], [1, 2])
	return {"kind": kind, "box": Vector2i(w, h1 + 3), "parts": [Rect2i(0, 0, w, h1), Rect2i(1, h1 - 1, 4, 4)], "margin": 0, "fy": fy}


static func _plan_church(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var nw := _r(rng, [9, 10])
	if nw + 2 > avail_w:
		nw = avail_w - 2
	if nw < 9:
		return {}
	var fy := 2
	var nl := mini(14, depth - 7 - fy - 1)
	if nl < 9:
		return {}
	var aw := nw - 2
	var xt := (nw - 5) / 2
	return {"kind": kind, "box": Vector2i(nw, nl + 7), "parts": [Rect2i(xt, 0, 5, 5), Rect2i(0, 4, nw, nl), Rect2i((nw - aw) / 2, 4 + nl - 1, aw, 4)], "margin": _r(rng, [2, 5]), "fy": fy, "landmark": "bell_tower"}


static func _plan_school(kind: String, avail_w: int, depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var mw := _r(rng, [18, 22])
	if mw > avail_w:
		mw = avail_w
	if mw < 17:
		return {}
	var mh := 9
	var rw := 9
	var fy := 2
	var rh := mini(9, depth - fy - mh + 1 - 3)
	if rh < 7:
		return {}
	var xr := 0 if rng.randf() < 0.5 else mw - rw
	return {"kind": kind, "box": Vector2i(mw, mh + rh - 1), "parts": [Rect2i(0, 0, mw, mh), Rect2i(xr, mh - 1, rw, rh)], "margin": _r(rng, [2, 4]), "fy": fy}


# ====================================================================== programs ==

## The kinds whose parts are laid out by `BuildingGen._layout_part` (rooms of at least 3 x 3 floor tiles, doors planned between neighbours, a hall down the middle where the part is big
## enough and its program starts with one): the homes. The rest (shops, flats, works, terraces) use the older partition by shares.
const ROOMY := ["start", "family", "medium", "small", "bungalow", "lhouse", "thouse", "uhouse", "twowing", "farmhouse"]
## The kinds a survivor may be found in (the rescue houses): family homes and the bigger detached ones, never a cottage, a terrace, a shed.
const RESCUE_KINDS := ["family", "bungalow", "lhouse", "thouse", "uhouse", "twowing", "medium", "farmhouse"]
## Which wing of a house a room belongs in: the day rooms on one side of the hall, the night ones on the other.
const NIGHT_ROOMS := ["bedroom", "bathroom", "nursery"]


static func is_roomy(kind: String) -> bool:
	return ROOMY.has(kind)


## A room of a program: name, the share of the floor, the floor, flags ("e" the front door opens into it, "f" it wants the front of its part, "b" the back).
static func it(name: String, share: float, floor_name: String, flags: String = "") -> Dictionary:
	return {"name": name, "share": share, "floor": floor_name, "entry": "e" in flags, "pref": -1 if "f" in flags else (1 if "b" in flags else 0)}


## The rooms of a kind, one list for each part (in the order of the plan's parts); the first of a list is the first to be kept when the part is too small for them all.
static func programs(kind: String, rng: RandomNumberGenerator) -> Array:
	match kind:
		"start":
			# the family home of the start: a hall down the middle, the day rooms on one side of it (the living room at the front, the kitchen, the utility room where the bench goes) and the
			# night ones on the other (three bedrooms and the bathroom)
			return [[it("hall", 2.0, "WOOD", "e"), it("living room", 3.4, "WOOD", "f"), it("kitchen", 2.4, "KITCHEN", "b"), it("bedroom", 2.6, "WOOD", "b"), it("bedroom", 2.4, "WOOD", "b"),
				it("bathroom", 1.2, "KITCHEN", "b"), it("utility", 1.6, "LINO", "b"), it("bedroom", 2.2, "WOOD", "b")]]
		"family":
			var third: Array = [it("utility", 1.6, "LINO", "b"), it("dining room", 1.8, "WOOD", "b"), it("study", 1.6, "WOOD", "b")]
			var first := rng.randi() % 3
			return [[it("hall", 2.0, "WOOD", "e"), it("living room", 3.4, "WOOD", "f"), it("kitchen", 2.4, "KITCHEN", "b"), it("bedroom", 2.6, "WOOD", "b"), it("bedroom", 2.4, "WOOD", "b"),
				it("bathroom", 1.2, "KITCHEN", "b"), third[first], it("bedroom", 2.2, "WOOD", "b"), third[(first + 1) % 3]]]
		"medium":
			var m: Array = [it("living room", 3.0, "WOOD", "ef"), it("kitchen", 2.0, "KITCHEN", "b"), it("bedroom", 2.4, "WOOD", "b"), it("bathroom", 1.1, "KITCHEN", "b"), it("bedroom", 2.2, "WOOD", "b")]
			m.insert(2, it("dining room", 1.6, "WOOD") if rng.randf() < 0.5 else it("study", 1.4, "WOOD"))
			return [m]
		"small":
			var l := [it("living room", 3.0, "WOOD", "ef"), it("bedroom", 2.2, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b"), it("bedroom", 2.0, "WOOD", "b")]
			l.insert(1, it("kitchen", 1.8, "KITCHEN", "b"))
			return [l]
		"bungalow":
			return [[it("hall", 2.0, "WOOD", "e"), it("living room", 3.2, "WOOD", "f"), it("kitchen", 2.2, "KITCHEN", "b"), it("bedroom", 2.4, "WOOD", "b"), it("bathroom", 1.1, "KITCHEN", "b"), it("bedroom", 2.2, "WOOD", "b"),
				it("dining room", 1.6, "WOOD", "b")], [it("garage", 1.0, "CONCRETE", "ef")]]
		"lhouse":
			return [[it("living room", 3.0, "WOOD", "ef"), it("kitchen", 2.2, "KITCHEN"), it("dining room", 1.8, "WOOD")], [it("bedroom", 2.4, "WOOD"), it("bedroom", 2.4, "WOOD"), it("bathroom", 1.1, "KITCHEN"), it("study", 1.4, "WOOD")]]
		"thouse":
			return [[it("living room", 3.0, "WOOD", "ef"), it("kitchen", 2.2, "KITCHEN"), it("study", 1.6, "WOOD"), it("dining room", 1.8, "WOOD")], [it("bedroom", 2.4, "WOOD"), it("bedroom", 2.2, "WOOD"), it("bathroom", 1.1, "KITCHEN"), it("utility", 1.4, "LINO")]]
		"uhouse":
			# (the wings are at the front: the front door is in the left one)
			return [[it("kitchen", 2.2, "KITCHEN"), it("dining room", 2.0, "WOOD"), it("bedroom", 2.2, "WOOD"), it("utility", 1.4, "LINO")], [it("living room", 3.0, "WOOD", "ef"), it("study", 1.4, "WOOD")],
				[it("bedroom", 2.2, "WOOD"), it("bedroom", 2.2, "WOOD"), it("bathroom", 1.1, "KITCHEN")]]
		"twowing":
			return [[it("living room", 3.0, "WOOD", "ef"), it("kitchen", 2.2, "KITCHEN"), it("dining room", 1.6, "WOOD"), it("study", 1.4, "WOOD")], [it("bedroom", 2.4, "WOOD"), it("bedroom", 2.4, "WOOD"), it("bathroom", 1.1, "KITCHEN"), it("nursery", 1.4, "WOOD")]]
		"terrace":
			return [[it("front room", 3.0, "WOOD", "ef"), it("kitchen", 2.0, "KITCHEN", "b"), it("bedroom", 2.2, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"cottage":
			return [[it("living room", 3.0, "WOOD", "ef"), it("bedroom", 2.0, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"terrace_ext":
			return [[it("front room", 3.0, "WOOD", "ef"), it("bedroom", 2.0, "WOOD", "b")], [it("kitchen", 1.0, "KITCHEN")]]
		"cornershop", "shop", "pharmacy", "rowshop":
			return [[it("shop floor", 6.0, "LINO", "ef"), it("storeroom", 2.0, "WOOD", "b"), it("office", 1.4, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"shed":
			return [[it("shed", 2.0, "WOOD", "ef"), it("store", 1.0, "WOOD", "b")]]
		"kiosk":
			return [[it("shop floor", 3.0, "LINO", "ef"), it("storeroom", 1.5, "WOOD", "b")]]
		"bakery":
			return [[it("shop floor", 4.0, "LINO", "ef"), it("kitchen", 3.0, "KITCHEN", "b"), it("storeroom", 1.0, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"hardware":
			return [[it("shop floor", 6.0, "LINO", "ef"), it("storeroom", 3.0, "CONCRETE", "b"), it("office", 1.5, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"diner":
			return [[it("dining hall", 6.0, "LINO", "ef"), it("kitchen", 2.4, "KITCHEN", "b"), it("storeroom", 1.2, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"bank":
			return [[it("banking hall", 4.0, "TERRAZZO", "ef"), it("office", 2.0, "WOOD", "b"), it("vault", 1.4, "CONCRETE", "b")]]
		"office":
			return [[it("reception", 2.0, "TERRAZZO", "ef"), it("office", 3.0, "WOOD", "b"), it("office", 3.0, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"supermarket":
			return [[it("shop floor", 9.0, "LINO", "ef"), it("storeroom", 3.0, "CONCRETE", "b"), it("office", 1.2, "WOOD", "b")]]
		"library":
			return [[it("reading room", 5.0, "WOOD", "ef"), it("stacks", 4.0, "WOOD", "b"), it("office", 1.5, "WOOD", "b")]]
		"clinic":
			return [[it("waiting room", 4.0, "TERRAZZO", "ef"), it("ward", 3.0, "TERRAZZO", "b"), it("ward", 3.0, "TERRAZZO", "b"), it("pharmacy", 2.0, "TERRAZZO", "b"), it("bathroom", 1.0, "KITCHEN", "b"), it("office", 1.5, "WOOD", "b")]]
		"fire_station":
			return [[it("engine bay", 8.0, "CONCRETE", "ef"), it("dormitory", 3.0, "WOOD", "b"), it("kitchen", 2.0, "KITCHEN", "b"), it("office", 1.6, "WOOD", "b")]]
		"police":
			return [[it("front desk", 4.0, "TERRAZZO", "ef"), it("cell", 1.5, "CONCRETE", "b"), it("cell", 1.5, "CONCRETE", "b"), it("armoury", 2.0, "CONCRETE", "b"), it("office", 2.0, "WOOD", "b"), it("bathroom", 1.0, "KITCHEN", "b")]]
		"warehouse":
			return [[it("hall", 10.0, "CONCRETE", "e"), it("office", 1.6, "WOOD", "b")]]
		"garage":
			return [[it("workshop", 7.0, "CONCRETE", "ef"), it("office", 2.0, "WOOD", "b"), it("storeroom", 1.5, "CONCRETE", "b")]]
		"workshop":
			return [[it("workshop", 5.0, "CONCRETE", "ef"), it("storeroom", 2.0, "CONCRETE", "b")]]
		"scrapyard", "containers":
			return [[it("office", 2.0, "WOOD", "ef"), it("storeroom", 1.0, "CONCRETE", "b")]]
		"farmhouse":
			return [[it("kitchen", 2.2, "KITCHEN", "ef"), it("living room", 3.0, "WOOD"), it("bedroom", 2.4, "WOOD", "b"), it("bedroom", 2.2, "WOOD", "b"), it("pantry", 1.0, "KITCHEN", "b")], [it("bedroom", 2.4, "WOOD"), it("bathroom", 1.0, "KITCHEN"), it("bedroom", 2.0, "WOOD")]]
		"barn":
			return [[it("barn", 3.0, "DIRT", "ef"), it("stable", 1.2, "DIRT", "b")]]
		"church":
			return [[it("narthex", 1.0, "WOOD", "e")], [it("nave", 1.0, "WOOD")], [it("chancel", 1.0, "TERRAZZO")]]
		"school":
			return [[], [it("gym", 4.0, "CONCRETE"), it("storeroom", 1.0, "CONCRETE", "b")]]
	return [[it("room", 1.0, "WOOD", "e")]]
