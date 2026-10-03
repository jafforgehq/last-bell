## The road of the live drive (round 21): `RoadGen.make(place, seed, leg, ctx)` draws the strip of ground between the base and a
## place as a SITE in the shape of site_gen.gd (so `World.build(site.data)` and `RaidRun` take it as they take a place), with a
## `road` dictionary the drive scene and the car's autopilot read. Read the data in assets/data/road_layouts.json.
##
##   {"name": "The road to The pharmacy", "kind": "road", "size": Vector2i(30, len + 24), "data": a map (SiteGen.map_data),
##    "entry": the leg's start, "entry_spread", "exit": Rect2 (6 rows, the whole width, from the leg's end onward),
##    "vehicle_spot": (-1, -1), "containers": [], "dead": [stragglers], "rooms": [], "seed", "danger",
##    "road": {"len", "width", "style", "start", "end", "dir", "centerline", "path", "slots", "dyn", "ambient", "leg"}}
##
## The strip runs north to south, 30 tiles across; the leg's `start` and `end` are the two ends of the road, `margin` (12) rows from
## the strip's edges, `len` rows apart (`road.len` is the length of the centre line itself, a little more). The way there starts at
## the south end and runs north (`dir` -1), the way home is the same ground the other way (`dir` +1). The carriageway is 8 wide with
## a 2-wide verge each side; its centre follows a gentle double sine of the strip's row. Everything standing about the road keeps
## 3 tiles from the centre line, so a car-wide line (the `path`) always exists; what the plan puts down (a roadblock's wall, a
## stop's props) is placed on top of that ground, clearing the ambient props it lands on. Deterministic in (place, seed, leg, ctx).
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Canvas := preload("res://scripts/raid/site_canvas.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")

const LAYOUTS_PATH := "res://assets/data/road_layouts.json"
const EVENTS_PATH := "res://scripts/drive/road_events.gd"
## The longest strip, in rows of road (place_flow.gd's MAX_STRIP), and the real seconds a leg takes at cruise at its shortest and longest
## (the same rule: `len` is leg seconds x cruise).
const MAX_STRIP := 700
const LEG_MIN_S := 30.0
const LEG_MAX_S := 90.0
## How many times a strip that fails its proof is made again (with another throw of the events' dice) before its wrecks are dropped.
const ATTEMPTS := 5
## The width the proof is made for: a bus (2.6 wide) on a vehicle's road, a person (1.2) on foot.
const CAR_WIDTH := 2.6
const FOOT_WIDTH := 1.2
## How far everything standing about the road keeps from its centre line (the carriageway is 4 each side, the verge 2 more).
const KEEP_CLEAR := 3.0

static var _lay: Dictionary = {}
static var _tids: Dictionary = {}
static var _offsets: Dictionary = {}


static func layouts() -> Dictionary:
	if _lay.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Could not read %s" % LAYOUTS_PATH)
			return {}
		_lay = parsed
	return _lay


## The style of the country about the road to a place, by its kind: "urban" (the rest), "rural" or "industrial".
static func style_of(place: Dictionary) -> String:
	var kind := String(place.get("kind", ""))
	var styles: Dictionary = layouts().styles
	for s in styles:
		if kind in styles[s].kinds:
			return String(s)
	return "urban"


## Rows of road for a leg: `ctx.len` (place_flow.gd's strip_len) when it has one, else made as it is: the leg's seconds at cruise.
static func len_for(ctx: Dictionary) -> int:
	if ctx.has("len"):
		return clampi(int(ctx.len), 40, MAX_STRIP)
	var secs := clampf(float(ctx.get("road_min", 60.0)), LEG_MIN_S, LEG_MAX_S)
	return clampi(mini(roundi(secs * float(ctx.get("cruise", 3.2))), MAX_STRIP), 40, MAX_STRIP)


static func _hash(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h


# -------------------------------------------------------------------- make --

static func make(place: Dictionary, seed: int, leg: String, ctx: Dictionary) -> Dictionary:
	var width := CAR_WIDTH if String(ctx.get("kind", "")) != "" else FOOT_WIDTH
	for salt in ATTEMPTS:
		var site := _build(place, seed, leg, ctx, salt, false)
		if passable(site, width):
			return site
	# nothing passed: the wrecks go (the way is the road itself)
	return _build(place, seed, leg, ctx, 0, true)


static func _tids_of() -> Dictionary:
	if _tids.is_empty():
		var base := GD.load_all()
		for k in base.terrainTypes:
			_tids[k] = int(base.terrainTypes[k].id)
		var lay := SiteGen.layouts()
		for k in lay.terrain:
			_tids[k] = int(lay.terrain[k].id)
	return _tids


## The centre line's parameters for a strip: the phases, the base and the scale that keeps it from running steeper than `max_slope`.
static func _geometry(key: int, cfg: Dictionary, H: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash("geo|%d" % key)
	var waves: Array = cfg.waves
	var phases: Array = []
	for w in waves:
		phases.append(rng.randf() * TAU)
	var geo := {
		"base": float(cfg.base) + rng.randf_range(-float(cfg.base_jitter), float(cfg.base_jitter)),
		"waves": waves,
		"phases": phases,
		"scale": 1.0,
	}
	var peak := 0.0
	for k in H * 4:
		var slope := 0.0
		for i in waves.size():
			var amp := float(waves[i][0])
			var period := float(waves[i][1])
			slope += amp * TAU / period * cos(TAU * float(k) * 0.25 / period + float(phases[i]))
		peak = maxf(peak, absf(slope))
	var max_slope := float(cfg.max_slope)
	if peak > max_slope:
		geo["scale"] = max_slope / peak
	return geo


## The x of the road's centre at a row coordinate (a float: row `y` spans y to y + 1).
static func _c(geo: Dictionary, y: float) -> float:
	var sum := 0.0
	var waves: Array = geo.waves
	for i in waves.size():
		sum += float(waves[i][0]) * sin(TAU * y / float(waves[i][1]) + float(geo.phases[i]))
	return float(geo.base) + float(geo.scale) * sum


## The tile column the carriageway is centred on in a row (it spans cr - 4 to cr + 3).
static func _cr(geo: Dictionary, row: int) -> int:
	return roundi(_c(geo, float(row) + 0.5))


static func _pick(table: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var at := rng.randf() * total
	var last := ""
	for k in table:
		last = String(k)
		at -= float(table[k])
		if at < 0.0:
			return last
	return last


static func _build(place: Dictionary, seed: int, leg: String, ctx: Dictionary, salt: int, drop_wrecks: bool) -> Dictionary:
	var lay := layouts()
	var cfg: Dictionary = lay.geometry
	var site_lay := SiteGen.layouts()
	var W := int(cfg.width)
	var margin := int(cfg.margin)
	var len_t := len_for(ctx)
	var H := len_t + 2 * margin
	var key := _hash("%s|%d" % [String(place.get("id", place.get("name", ""))), seed])
	var style_id := style_of(place)
	var style: Dictionary = lay.styles[style_id]
	var danger := int(ctx.get("danger", place.get("danger", 1)))
	var by_vehicle := String(ctx.get("kind", "")) != ""
	var dir := 1 if leg == "home" else -1
	var geo := _geometry(key, cfg, H)

	var cv := Canvas.new()
	cv.setup(W, H, key, site_lay.props, _tids_of(), site_lay.get("templates", {}))
	cv.danger = danger
	_ground(cv, geo, cfg, style)
	_ambient(cv, geo, cfg, lay, style, danger, len_t)

	# the leg: the road's two ends, the centre line from the start
	var start_y := float(H - margin) if dir < 0 else float(margin)
	var plan: Array = _sorted_plan(ctx.get("plan", []))
	var events := _events(cv, geo, lay, cfg, plan, key, leg, salt, start_y, dir, len_t, by_vehicle, drop_wrecks)
	var centerline := PackedVector2Array()
	var path := PackedVector2Array()
	var arc := 0.0
	for i in len_t + 1:
		var y := start_y + float(dir * i)
		var cx := _c(geo, y)
		centerline.append(Vector2(cx, y))
		path.append(Vector2(cx + _shift(events.knots, float(i)), y))
		if i > 0:
			arc += centerline[i].distance_to(centerline[i - 1])
	var start: Vector2 = centerline[0]
	var end: Vector2 = centerline[len_t]
	var dead := _dead(cv, geo, lay, danger, len_t, start_y, dir, key, leg, salt, start)

	var exit_rows := float(cfg.exit_rows)
	var exit_rect := Rect2(0.0, end.y - exit_rows, float(W), exit_rows) if dir < 0 else Rect2(0.0, end.y, float(W), exit_rows)
	var data := SiteGen.map_data(cv, start, {})
	var ambient: Array = []
	if ctx.has("ambient"):
		ambient = ctx.ambient
	else:
		ambient = _ambient_for(ctx)
	return {
		"name": "The road to %s" % String(place.get("name", "the place")),
		"kind": "road",
		"size": Vector2i(W, H),
		"data": data,
		"entry": start,
		"entry_spread": 0.9,
		"exit": exit_rect,
		"vehicle_spot": Vector2(-1.0, -1.0),
		"containers": [],
		"dead": dead,
		"rooms": [],
		"seed": seed,
		"danger": danger,
		"road": {
			"len": arc,
			"width": W,
			"style": style_id,
			"start": start,
			"end": end,
			"dir": dir,
			"centerline": centerline,
			"path": path,
			"slots": events.slots,
			"dyn": events.dyn,
			"ambient": ambient,
			"leg": leg,
		},
	}


## The night road (RoadEvents.ambient_for) for a context, when the events' module is there to say.
static func _ambient_for(ctx: Dictionary) -> Array:
	if not ResourceLoader.exists(EVENTS_PATH):
		return []
	var events = load(EVENTS_PATH)
	if events == null:
		return []
	for m in events.get_script_method_list():
		if String(m.name) == "ambient_for":
			var out = events.ambient_for(ctx)
			return out if out is Array else []
	return []


static func _sorted_plan(plan: Array) -> Array:
	var out: Array = plan.duplicate()
	out.sort_custom(func(a, b): return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	return out


# ------------------------------------------------------------------ ground --

## The ground: the country, the carriageway and its verge row by row, the lane lines, the solid edges.
static func _ground(cv, geo: Dictionary, cfg: Dictionary, style: Dictionary) -> void:
	var W: int = cv.W
	var H: int = cv.H
	var ground := String(style.ground)
	cv.fill(Rect2i(0, 0, W, H), ground)
	var carriage := int(cfg.carriage)
	var verge := int(cfg.verge)
	var half := carriage >> 1
	for y in H:
		var cr := _cr(geo, y)
		cv.fill(Rect2i(cr - half - verge, y, carriage + 2 * verge, 1), String(style.verge))
		cv.fill(Rect2i(cr - half, y, carriage, 1), String(style.carriage))
	for patch in style.get("patches", []):
		_patches(cv, geo, patch, H)
	# the lines painted down the road, in short straight pieces that follow the centre (a gap now and again, worn)
	var seg := int(cfg.lane_seg)
	var skip_every := int(cfg.lane_skip_every)
	var n := 0
	var y0 := int(cfg.cap)
	while y0 + seg <= H - int(cfg.cap):
		if skip_every <= 0 or n % skip_every != skip_every - 1:
			var ym := float(y0) + float(seg) / 2.0
			cv.marks.append({"kind": "lanes", "cx": _c(geo, ym), "cy": ym, "w": float(cfg.lane_w), "h": float(seg), "dir": "v", "gaps": [], "seed": cv.rng.randi() % 2000000})
		n += 1
		y0 += seg
	# the solid edges: the columns at the sides and the rows at the ends
	var border := int(cfg.border)
	var cap := int(cfg.cap)
	cv.fill(Rect2i(0, 0, border, H), ground, true)
	cv.fill(Rect2i(W - border, 0, border, H), ground, true)
	cv.fill(Rect2i(0, 0, W, cap), ground, true)
	cv.fill(Rect2i(0, H - cap, W, cap), ground, true)


## Round patches of other ground in the country beside the road (dirt in the grass, soil, oil).
static func _patches(cv, geo: Dictionary, patch: Dictionary, H: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var n_range: Array = patch.n
	var span: Array = patch.r
	var tid := int(_tids_of()[String(patch.t)])
	var y := 8
	while y < H - 8:
		var n := rng.randi_range(int(n_range[0]), int(n_range[1]))
		for k in n:
			var py := y + rng.randi_range(0, 23)
			if py >= H - 4:
				continue
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var cx := _c(geo, float(py) + 0.5) + side * rng.randf_range(8.0, 13.0)
			var rad := rng.randf_range(float(span[0]), float(span[1]))
			for yy in range(int(float(py) - rad) - 1, int(float(py) + rad) + 2):
				for xx in range(int(cx - rad) - 1, int(cx + rad) + 2):
					if not cv.is_open(xx, yy):
						continue
					if absf(float(xx) + 0.5 - _c(geo, float(yy) + 0.5)) < 6.5:
						continue
					var d := Vector2(float(xx) - cx, (float(yy) - float(py)) * 1.2).length() + rng.randf() * 0.8
					if d <= rad:
						cv.terrain[yy * cv.W + xx] = tid
		y += 24


# ----------------------------------------------------------------- ambient --

static func _clear_of_road(geo: Dictionary, x: float, y: float, margin: float = 0.0) -> bool:
	return absf(x - _c(geo, y)) >= KEEP_CLEAR + margin


static func _free(cv, x: int, y: int, w: int, h: int, border: int = 2, cap: int = 3) -> bool:
	if x < border or x + w > cv.W - border or y < cap or y + h > cv.H - cap:
		return false
	for yy in h:
		for xx in w:
			if cv.solid[(y + yy) * cv.W + x + xx] != 0:
				return false
	return true


static func _budget_left(cv, total: int) -> int:
	return total - cv.objects.size() - cv.trees.size()


## Everything that stands about the road whatever the plan: buildings and fields (ground), cars, props, trees, decals.
static func _ambient(cv, geo: Dictionary, cfg: Dictionary, lay: Dictionary, style: Dictionary, danger: int, len_t: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	var hundreds := float(len_t) / 100.0
	var total := roundi(float(lay.budget.per_row) * float(H))
	# fields and the buildings: ground only, no sprites
	if style.has("fields"):
		_fields(cv, geo, style.fields)
	if style.has("buildings"):
		_buildings(cv, geo, style.buildings)
	# the cars standing about: counted for the danger first, the rest takes what the budget leaves
	var wr: Dictionary = lay.wrecks
	var n_cars := roundi((float(wr.base) + float(wr.per_danger) * float(danger)) * hundreds)
	_wrecks(cv, geo, wr, n_cars)
	var n_dead_bodies := roundi(float(wr.corpses_per_danger) * float(danger) * hundreds)
	var wanted := 0.0
	var scatter: Array = style.get("scatter", [])
	for sc in scatter:
		wanted += float(sc.per100) * hundreds
	wanted += float(style.get("trees", 0.0)) * hundreds + float(cfg.border_trees) * 2.0 * float(H)
	wanted += float(style.get("fences", 0.0)) * hundreds * 4.0
	wanted += float(style.decals.per100) * hundreds + float(n_dead_bodies)
	var room := maxi(0, _budget_left(cv, total))
	var scale := 1.0 if wanted <= float(room) else float(room) / maxf(wanted, 1.0)
	for sc in scatter:
		_scatter(cv, geo, sc, roundi(float(sc.per100) * hundreds * scale))
	_trees(cv, geo, roundi(float(style.get("trees", 0.0)) * hundreds * scale))
	_border_trees(cv, cfg, scale)
	if float(style.get("fences", 0.0)) > 0.0:
		_fences(cv, geo, roundi(float(style.fences) * hundreds * scale))
	_decals(cv, geo, style.decals, roundi(float(style.decals.per100) * hundreds * scale), n_dead_bodies)
	# the road's two ends are shut by a line of trees
	for x in range(3, cv.W - 2, 3):
		cv._add_tree(x, 1)
		cv._add_tree(x, H - 2)


## Roofed blocks on one side of the road or the other, as wide as the room beside the road allows: the ground only (the walls and
## the roof are terrain).
static func _buildings(cv, geo: Dictionary, b: Dictionary) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	var items: Array = b.items
	var weights := {}
	for i in items.size():
		weights[str(i)] = float(items[i].k)
	var front: Array = b.front
	var between: Array = b.between
	var min_w := int(b.get("min_w", 4))
	var stamps := 0
	var y := rng.randi_range(5, 16)
	while y < H - 14:
		if rng.randf() < float(b.skip):
			y += rng.randi_range(4, 10)
			continue
		var it: Dictionary = items[int(_pick(weights, rng))]
		if it.has("stamp") and stamps >= int(it.get("max", 3)):
			it = items[0]
		var w_want := rng.randi_range(int(it.w[0]), int(it.w[1]))
		var h := rng.randi_range(int(it.h[0]), int(it.h[1]))
		var gap := rng.randi_range(int(front[0]), int(front[1]))
		var side := 1 if rng.randf() < 0.5 else -1
		var placed := false
		for s in [side, -side]:
			var w := mini(w_want, _side_room(cv, geo, y, h, s) - gap)
			if w < min_w:
				continue
			var x0 := _side_x(cv, geo, y, h, s, w, gap)
			if x0 >= 0 and it.has("stamp"):
				# a house of the places' own (doors, rooms, furniture), where the room is exactly its size
				if w == int(it.w[0]) and _free(cv, x0, y, w, h, 3, 4):
					cv._run_ops([{"op": "stamp", "template": String(it.stamp), "at": [x0, y]}])
					stamps += 1
					placed = true
					break
				continue
			if x0 >= 0 and _free(cv, x0, y, w, h, 3, 4):
				var walls: Array = it.wall
				var wall := String(walls[rng.randi() % walls.size()])
				cv._run_ops([{"op": "block", "rect": [x0, y, w, h], "wall": wall, "roof": String(it.roof)}])
				placed = true
				break
		y += (h if placed else 3) + rng.randi_range(int(between[0]), int(between[1]))


## The free width beside the verge on one side for the rows y to y + h - 1 (down to the strip's edge columns).
static func _side_room(cv, geo: Dictionary, y: int, h: int, side: int) -> int:
	var lo := 1000
	var hi := -1000
	for row in range(y, mini(y + h, cv.H)):
		var cr := _cr(geo, row)
		lo = mini(lo, cr)
		hi = maxi(hi, cr)
	if side > 0:
		return cv.W - 3 - (hi + 6)
	return (lo - 6) - 3


## The left column of a w-wide thing standing `gap` tiles beyond the verge on one side for the rows y to y + h - 1, or -1 for no room.
static func _side_x(cv, geo: Dictionary, y: int, h: int, side: int, w: int, gap: int) -> int:
	var lo := 1000
	var hi := -1000
	for row in range(y, mini(y + h, cv.H)):
		var cr := _cr(geo, row)
		lo = mini(lo, cr)
		hi = maxi(hi, cr)
	if side > 0:
		var x0 := hi + 6 + gap
		return x0 if x0 + w <= cv.W - 3 else -1
	var x1 := lo - 6 - gap
	var xs := x1 - w
	return xs if xs >= 3 else -1


## Ploughed fields beyond the verge (soil under the grass), as wide as the room allows: ground only.
static func _fields(cv, geo: Dictionary, f: Dictionary) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	var front: Array = f.front
	var between: Array = f.between
	var y := rng.randi_range(5, 14)
	while y < H - 14:
		if rng.randf() < float(f.skip):
			y += rng.randi_range(4, 10)
			continue
		var w_want := rng.randi_range(int(f.w[0]), int(f.w[1]))
		var h := rng.randi_range(int(f.h[0]), int(f.h[1]))
		var gap := rng.randi_range(int(front[0]), int(front[1]))
		var side := 1 if rng.randf() < 0.5 else -1
		var h2 := mini(h, H - 4 - y)
		var placed := false
		for s in [side, -side]:
			var w := mini(w_want, _side_room(cv, geo, y, h2, s) - gap)
			if w < 3:
				continue
			var x0 := _side_x(cv, geo, y, h2, s, w, gap)
			if x0 >= 0:
				cv.fill(Rect2i(x0, y, w, h2), String(f.t))
				placed = true
				break
		y += (h2 if placed else 3) + rng.randi_range(int(between[0]), int(between[1]))


## The cars standing about: along the verge (lying beside the road) or in the country beyond, wrecked or parked.
static func _wrecks(cv, geo: Dictionary, wr: Dictionary, n: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	for i in n:
		var verge := rng.randf() < float(wr.verge_share)
		var kind := _pick(wr.verge if verge else wr.beyond, rng)
		var fp: Vector2i = cv.tiles_of(kind)
		for attempt in 10:
			var y := rng.randi_range(4, H - 4 - fp.y)
			var side := 1 if rng.randf() < 0.5 else -1
			var cr := _cr(geo, y + (fp.y >> 1))
			var x := 0
			if verge:
				x = cr + 4 if side > 0 else cr - 4 - fp.x
			else:
				var gap := rng.randi_range(0, 3)
				x = _side_x(cv, geo, y, fp.y, side, fp.x, gap)
				if x < 0:
					continue
			if not _verge_clear(cv, geo, x, y, fp):
				continue
			if cv._put(kind, x, y, {"force": true}) != null:
				break


## Whether a footprint keeps clear of the road's middle in every row it covers (nearest edge KEEP_CLEAR from the centre line).
static func _verge_clear(cv, geo: Dictionary, x: int, y: int, fp: Vector2i) -> bool:
	for row in range(y, y + fp.y):
		var c := _c(geo, float(row) + 0.5)
		var near := minf(absf(float(x) - c), absf(float(x + fp.x) - c))
		if float(x) < c and float(x + fp.x) > c:
			return false
		if near < KEEP_CLEAR:
			return false
	return true


static func _scatter(cv, geo: Dictionary, sc: Dictionary, n: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	var verge := String(sc.zone) == "verge"
	for i in n:
		var kind := _pick(sc.kinds, rng)
		var fp: Vector2i = cv.tiles_of(kind)
		for attempt in 8:
			var y := rng.randi_range(5, H - 5 - fp.y)
			var side := 1 if rng.randf() < 0.5 else -1
			var cr := _cr(geo, y + (fp.y >> 1))
			var x := 0
			if verge:
				# the outer tile of the verge, or the inner
				var col := rng.randi_range(0, 1)
				x = cr + 4 + col if side > 0 else cr - 5 - col
				if fp.x > 1:
					x = cr + 4 if side > 0 else cr - 4 - fp.x
			else:
				var gap := rng.randi_range(0, 5)
				x = _side_x(cv, geo, y, fp.y, side, fp.x, gap)
				if x < 0:
					continue
			if not _verge_clear(cv, geo, x, y, fp):
				continue
			if cv._put(kind, x, y, {"force": true}) != null:
				break


static func _trees(cv, geo: Dictionary, n: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	for i in n:
		for attempt in 10:
			var y := rng.randi_range(5, H - 5)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var x := floori(_c(geo, float(y) + 0.5) + side * rng.randf_range(6.0, 13.0))
			if x < 3 or x >= cv.W - 3 or not cv.is_open(x, y):
				continue
			if absf(float(x) + 0.5 - _c(geo, float(y) + 0.5)) < 6.0:
				continue
			if cv._props_near(x, y, 1, 1, 1):
				continue
			cv._add_tree(x, y)
			break


## A scatter of trees on the solid edge columns (the strip's sides are a wood).
static func _border_trees(cv, cfg: Dictionary, scale: float) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var p := float(cfg.border_trees) * scale
	var border := int(cfg.border)
	for side in 2:
		var last := -99
		for y in range(int(cfg.cap), cv.H - int(cfg.cap)):
			if y - last >= 3 and rng.randf() < p:
				var x: int = rng.randi_range(0, border - 1) if side == 0 else cv.W - 1 - rng.randi_range(0, border - 1)
				cv._add_tree(x, y)
				last = y


## Stretches of chain-link fence along the road's edge of the fields (pictures only, they shut nothing).
static func _fences(cv, geo: Dictionary, stretches: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	for i in stretches:
		var y := rng.randi_range(6, H - 40)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var n := rng.randi_range(3, 5)
		for k in n:
			var row := y + 5 * k
			if row + 5 >= H - 3:
				break
			var xc := _c(geo, float(row) + 2.5) + side * 7.0
			var tx := floori(xc)
			if tx < 3 or tx >= cv.W - 3:
				continue
			cv._decor("chain_v", tx, row, 0.0, 0.0)


## Marks on the carriageway (cracks, stains, paper, blood) and the dead lying on it for the danger.
static func _decals(cv, geo: Dictionary, spec: Dictionary, n: int, bodies: int) -> void:
	var rng: RandomNumberGenerator = cv.rng
	var H: int = cv.H
	for i in n:
		var kind := _pick(spec.kinds, rng)
		var y := rng.randi_range(4, H - 5)
		var x := floori(_c(geo, float(y) + 0.5) + rng.randf_range(-3.6, 3.6))
		if cv.is_open(x, y):
			cv._decor(kind, x, y, rng.randf_range(0.0, 0.5), rng.randf_range(0.0, 0.5))
	for i in bodies:
		var y := rng.randi_range(14, H - 14)
		var x := floori(_c(geo, float(y) + 0.5) + rng.randf_range(-3.0, 3.0))
		if cv.is_open(x, y):
			cv._put("corpse", x, y, {"force": true})


# ------------------------------------------------------------------ events --

## Takes away the ambient things that stand (shut props and trees, not ground and not flat pictures) in a rectangle of the strip.
static func _clear_rect(cv, r: Rect2i) -> void:
	var rect := Rect2(r)
	var kept: Array = []
	for o in cv.objects:
		if bool(o.solid):
			var fp := Rect2(float(o.cx) - float(o.w) / 2.0, float(o.cy) - float(o.h) / 2.0, float(o.w), float(o.h))
			if rect.intersects(fp):
				# (a prop that only crosses the rectangle comes away whole)
				var tx := roundi(float(o.cx) - float(o.w) / 2.0)
				var ty := roundi(float(o.cy) - float(o.h) / 2.0)
				for yy in int(o.h):
					for xx in int(o.w):
						var x := tx + xx
						var y := ty + yy
						if x >= 0 and y >= 0 and x < cv.W and y < cv.H:
							cv.solid[y * cv.W + x] = 0
							cv.pmask[y * cv.W + x] = 0
				continue
		kept.append(o)
	cv.objects = kept
	var kept_trees: Array = []
	for t in cv.trees:
		var tx2 := floori(float(t.x))
		var ty2 := floori(float(t.y))
		if r.has_point(Vector2i(tx2, ty2)):
			cv.solid[ty2 * cv.W + tx2] = 0
			cv.pmask[ty2 * cv.W + tx2] = 0
			continue
		kept_trees.append(t)
	cv.trees = kept_trees


## The plan's events laid on the ground: the slots, the wrecks of the blocks (`dyn`) and the knots the path bends by.
static func _events(cv, geo: Dictionary, lay: Dictionary, cfg: Dictionary, plan: Array, key: int, leg: String, salt: int, start_y: float, dir: int, len_t: int, by_vehicle: bool, drop_wrecks: bool) -> Dictionary:
	var slots: Array = []
	var dyn: Array = []
	var controls: Array = []
	var dyn_left := int(lay.budget.dyn_max)
	var prev_off := 0.0
	var prev_s := -1.0e9
	for entry in plan:
		var at := clampf(float(entry.get("at", 0.5)), 0.0, 1.0)
		var uid := String(entry.get("uid", "e%d" % slots.size()))
		var ev := RandomNumberGenerator.new()
		ev.seed = _hash("ev|%d|%s|%d|%s|%d" % [key, leg, salt, uid, int(entry.get("seed", 0))])
		var s_rows := at * float(len_t)
		var y_e := start_y + float(dir) * s_rows
		var row := clampi(floori(y_e), 6, cv.H - 7)
		var kind := String(entry.get("kind", "forced"))
		var slot := {"uid": uid, "id": String(entry.get("id", "")), "anchor": Vector2(_c(geo, float(row) + 0.5), float(row) + 0.5), "y": float(row) + 0.5, "gap": null, "spawn": Vector2.ZERO, "figure": null}
		slot["spawn"] = slot.anchor
		match kind:
			"block":
				var limit := absf(float(row) - prev_s) * 0.08 if prev_s > -1.0e8 else 1.0e9
				var made := _block(cv, geo, lay.block, row, by_vehicle, ev, dyn, uid, dyn_left, drop_wrecks, prev_off, limit)
				slot["gap"] = made.gap
				slot["anchor"] = made.anchor
				slot["spawn"] = made.anchor
				slot["y"] = float(row) + 0.5
				dyn_left -= int(made.dyn_used)
				prev_off = float(made.off)
				prev_s = float(row)
				controls.append({"s": absf(float(row) + 0.5 - start_y), "off": float(made.off)})
			"stop":
				_stop(cv, geo, slot, String(entry.get("id", "")), row, ev)
			"dead":
				var cr := _cr(geo, row)
				_clear_rect(cv, Rect2i(cr - 8, row - 10, 17, 21))
			_:
				pass
		slots.append(slot)
	# the knots the path bends by: flat at the gaps (a plateau), eased in and out
	var knots := _knots(controls, lay.block, float(len_t))
	return {"slots": slots, "dyn": dyn, "knots": knots}


## The path's lateral shift as a list of knots [s, shift] (s = rows from the start): plateaus at each gap, eased between and out.
static func _knots(controls: Array, blk: Dictionary, len_t: float) -> Array:
	var knots: Array = [[0.0, 0.0]]
	if controls.is_empty():
		knots.append([len_t, 0.0])
		return knots
	var plateau := float(blk.plateau)
	var ramp := float(blk.ramp)
	for i in controls.size():
		var c: Dictionary = controls[i]
		var near := 1.0e9
		if i > 0:
			near = minf(near, float(c.s) - float(controls[i - 1].s))
		if i < controls.size() - 1:
			near = minf(near, float(controls[i + 1].s) - float(c.s))
		var pl := minf(plateau, maxf(near / 2.0 - 1.0, 0.5))
		var a := float(c.s) - pl
		var b := float(c.s) + pl
		# ease from the last knot: down to nothing first when the way between is long
		var last: Array = knots[knots.size() - 1]
		var room := a - float(last[0])
		if float(last[1]) != 0.0 and room > 2.0 * ramp:
			knots.append([float(last[0]) + ramp, 0.0])
			knots.append([a - ramp, 0.0])
		elif float(last[1]) == 0.0 and room > ramp:
			knots.append([a - ramp, 0.0])
		knots.append([a, float(c.off)])
		knots.append([b, float(c.off)])
	var tail: Array = knots[knots.size() - 1]
	if float(tail[1]) != 0.0:
		knots.append([minf(float(tail[0]) + ramp, len_t), 0.0])
	knots.append([maxf(len_t, float(knots[knots.size() - 1][0]) + 0.01), 0.0])
	return knots


static func _shift(knots: Array, s: float) -> float:
	if knots.size() < 2:
		return 0.0
	for i in range(1, knots.size()):
		var b: Array = knots[i]
		if s <= float(b[0]):
			var a: Array = knots[i - 1]
			var span := float(b[0]) - float(a[0])
			if span <= 0.0001:
				return float(b[1])
			var t := clampf((s - float(a[0])) / span, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(a[1]), float(b[1]), t)
	return 0.0


## One wreck of a block's line: a car, a van or a bus placed on the strip with its footprint solid but no map object: the scene
## draws it and can move it (`dyn`). The dictionary is the contract's: id, file, pos, rot, size, tiles, ram_hp.
static func _dyn_piece(cv, kind: String, tx: int, ty: int, id: String, ev: RandomNumberGenerator, blk: Dictionary) -> Dictionary:
	var p: Dictionary = cv.props[kind]
	var fp: Vector2i = cv.tiles_of(kind)
	var files: Array = p.files
	var file := String(files[ev.randi() % files.size()])
	var path := "res://assets/%s/%s.png" % [String(p.get("dir", "objects")), file]
	var tex: Texture2D = GD.tex(path)
	var pw := float(tex.get_width())
	var ph := float(tex.get_height())
	var w := pw / float(p.get("ppt", 96))
	var h := ph / float(p.get("ppt", 96))
	if p.has("dw"):
		w = float(p.dw)
		h = w * ph / pw
	elif p.has("dh"):
		h = float(p.dh)
		w = h * pw / ph
	var tiles: Array = []
	for yy in fp.y:
		for xx in fp.x:
			var i: int = (ty + yy) * cv.W + tx + xx
			cv.solid[i] = 1
			cv.pmask[i] = 1
			tiles.append(i)
	var hp := float(blk.ram_hp_bus) if kind.begins_with("bus") else float(blk.ram_hp)
	return {
		"id": id,
		"block": String(id).get_slice("_w", 0),
		"kind": kind,
		"file": path,
		"pos": Vector2(float(tx) + float(fp.x) / 2.0 + float(p.get("dx", 0.03)), float(ty) + float(fp.y) / 2.0 + float(p.get("dy", 0.08))),
		"rot": ev.randf_range(-float(blk.tilt), float(blk.tilt)),
		"size": Vector2(w, h),
		"tiles": tiles,
		"ram_hp": hp,
	}


## Lays a roadblock across the strip at a row: a line of wrecks across the road (the scene's, `dyn`) and of other things beyond it,
## with one gap of whole tiles (4 for a car, 2 for a person) near the middle. Returns {"gap", "anchor", "off", "dyn_used"}.
static func _block(cv, geo: Dictionary, blk: Dictionary, r0: int, by_vehicle: bool, ev: RandomNumberGenerator, dyn: Array, uid: String, dyn_left: int, drop_wrecks: bool, prev_off: float, limit: float) -> Dictionary:
	var W: int = cv.W
	var border := 2
	var gap_w := int(blk.gap_car) if by_vehicle else int(blk.gap_foot)
	var half := int(blk.clear_rows) >> 1
	_clear_rect(cv, Rect2i(border, r0 - half, W - 2 * border, 2 * half + 1))
	var cr := _cr(geo, r0)
	var cx := _c(geo, float(r0) + 0.5)
	var off := ev.randf_range(-float(blk.offset), float(blk.offset))
	off = clampf(off, prev_off - limit, prev_off + limit)
	off = clampf(off, -float(blk.offset), float(blk.offset))
	var gl := clampi(roundi(cx + off - float(gap_w) / 2.0), cr - 4, cr + 4 - gap_w)
	var gr := gl + gap_w
	var used := 0
	var top := r0
	var bottom := r0 + 1
	# the line over the verge and the carriageway: wrecks of the scene's (while it has the room for them)
	var line_runs := [[cr - 6, gl], [gr, cr + 6]]
	for run in line_runs:
		var x := int(run[0])
		var stop := int(run[1])
		while x < stop:
			if cv.solid[r0 * W + x] != 0:
				x += 1
				continue
			var n := stop - x
			var kind := ""
			var table: Dictionary = {}
			for k in blk.line:
				if int(cv.tiles_of(String(k)).x) <= n:
					table[k] = blk.line[k]
			# the bigger ones first, as they fit
			var big := {}
			for k in table:
				if int(cv.tiles_of(String(k)).x) >= 5:
					big[k] = table[k]
			if not big.is_empty() and ev.randf() < 0.7:
				kind = _pick(big, ev)
			elif not table.is_empty():
				kind = _pick(table, ev)
			var placed := false
			if kind != "":
				var fp: Vector2i = cv.tiles_of(kind)
				var order: Array = range(fp.y)
				for i in range(order.size() - 1, 0, -1):
					var j := ev.randi_range(0, i)
					var tmp = order[i]
					order[i] = order[j]
					order[j] = tmp
				for o in order:
					var ty := r0 - int(o)
					if _free(cv, x, ty, fp.x, fp.y):
						if dyn_left - used > 0 and not drop_wrecks:
							dyn.append(_dyn_piece(cv, kind, x, ty, "%s_w%d" % [uid, dyn.size()], ev, blk))
							used += 1
						elif not drop_wrecks:
							cv._put(kind, x, ty, {"force": true})
						top = mini(top, ty)
						bottom = maxi(bottom, ty + fp.y)
						x += fp.x
						placed = true
						break
			if not placed:
				_seal_tile(cv, x, r0, ev)
				x += 1
	# beyond the verge, out to the strip's edge: what stands in the way (static)
	var outer_runs := [[border, cr - 6], [cr + 6, W - border]]
	for run in outer_runs:
		var x := int(run[0])
		var stop := int(run[1])
		while x < stop:
			if cv.solid[r0 * W + x] != 0:
				x += 1
				continue
			var n := stop - x
			var table := {}
			for k in blk.outer:
				if int(cv.tiles_of(String(k)).x) <= n:
					table[k] = blk.outer[k]
			var placed := false
			if not table.is_empty():
				var kind := _pick(table, ev)
				var fp: Vector2i = cv.tiles_of(kind)
				for o in fp.y:
					var ty := r0 - o
					if _free(cv, x, ty, fp.x, fp.y) and cv._put(kind, x, ty, {"force": true}) != null:
						top = mini(top, ty)
						bottom = maxi(bottom, ty + fp.y)
						x += fp.x
						placed = true
						break
			if not placed:
				_seal_tile(cv, x, r0, ev)
				x += 1
	# the line is whole along the row but for the gap
	for x in range(border, W - border):
		if x >= gl and x < gr:
			continue
		if cv.solid[r0 * W + x] == 0:
			_seal_tile(cv, x, r0, ev)
	var gap := Rect2(float(gl), float(top), float(gap_w), float(bottom - top))
	return {"gap": gap, "anchor": Vector2(float(gl) + float(gap_w) / 2.0, float(r0) + 0.5), "off": float(gl) + float(gap_w) / 2.0 - cx, "dyn_used": used}


## A single shut tile in a line: a barrel, or a tree where there is no room.
static func _seal_tile(cv, x: int, y: int, ev: RandomNumberGenerator) -> void:
	if cv.solid[y * cv.W + x] != 0:
		return
	if cv._put("barrel", x, y, {"force": true}) == null:
		cv._add_tree(x, y)


## What a stop puts by the road: a figure, a car, drums, a barrier, a smoke. `slot` gets figure, figures, props, mark, side.
static func _stop(cv, geo: Dictionary, slot: Dictionary, id: String, r0: int, ev: RandomNumberGenerator) -> void:
	var side := 1 if ev.randf() < 0.5 else -1
	var cr := _cr(geo, r0)
	var props: Array = []
	var figures: Array = []
	# the verge on the chosen side (two columns) and one more beyond: nothing else stands there
	var x_near := cr + 4 if side > 0 else cr - 7
	_clear_rect(cv, Rect2i(x_near, r0 - 6, 3, 13))
	var vx := cr + 4 if side > 0 else cr - 6       # the verge's two columns start here
	var vx3 := cr + 4 if side > 0 else cr - 7      # three columns, the verge and one beyond
	match id:
		"survivor":
			figures.append(Vector2(float(cr) + float(side) * 5.0 + (0.0 if side > 0 else 0.0), float(r0) + 0.5))
		"wreck_supplies":
			_prop(cv, props, "car_v", vx, r0 - 2)
			_prop(cv, props, "crate", cr + 6 if side > 0 else cr - 7, r0 + 3)
			_prop(cv, props, "crate", cr + 6 if side > 0 else cr - 7, r0 + 4)
			cv._decor("papers", vx, r0 + 3, 0.2, 0.2)
		"fuel_stash":
			_prop(cv, props, "pickup_v", vx, r0 - 2)
			for k in 3:
				_prop(cv, props, "barrel", cr + 6 if side > 0 else cr - 7, r0 - 3 + 2 * k)
			_prop(cv, props, "ibc", vx, r0 + 4)
		"checkpoint":
			_prop(cv, props, "sandbags", vx3, r0 - 3)
			_prop(cv, props, "sandbags", vx3, r0 + 3)
			_prop(cv, props, "barrel", cr + 6 if side > 0 else cr - 7, r0)
			figures.append(Vector2(float(cr) + float(side) * 5.0, float(r0) - 0.5))
			figures.append(Vector2(float(cr) + float(side) * 5.0, float(r0) + 1.5))
		"smoke":
			_prop(cv, props, "barrel", vx + 1, r0)
			var burnt = cv._decor("scorch", vx, r0 - 1, 0.3, 0.3)
			if burnt != null:
				props.append({"kind": "scorch", "pos": Vector2(float(burnt.cx), float(burnt.cy))})
			var burnt2 = cv._decor("scorch", vx + 1, r0 + 1, 0.2, 0.0)
			if burnt2 != null:
				props.append({"kind": "scorch", "pos": Vector2(float(burnt2.cx), float(burnt2.cy))})
			cv._decor("papers", vx, r0 + 2, 0.1, 0.4)
		_:
			_prop(cv, props, "barrel", vx + 1, r0)
			cv._decor("papers", vx, r0 + 1, 0.2, 0.2)
	slot["props"] = props
	slot["side"] = side
	slot["figures"] = figures
	slot["figure"] = figures[0] if not figures.is_empty() else null
	var mark := Vector2(float(slot.anchor.x) + float(side) * 5.0, float(slot.anchor.y))
	if not figures.is_empty():
		mark = figures[0]
	elif not props.is_empty():
		mark = props[0].pos
	slot["mark"] = mark


static func _prop(cv, props: Array, kind: String, x: int, y: int) -> void:
	var o = cv._put(kind, x, y, {"force": true})
	if o != null:
		props.append({"kind": kind, "pos": Vector2(float(o.cx), float(o.cy))})


# -------------------------------------------------------------------- dead --

## The stragglers of the strip, "still" or "wandering", none within `keep_from_start` of the leg's start.
static func _dead(cv, geo: Dictionary, lay: Dictionary, danger: int, len_t: int, start_y: float, dir: int, key: int, leg: String, salt: int, start: Vector2) -> Array:
	var d: Dictionary = lay.dead
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash("dead|%d|%s|%d" % [key, leg, salt])
	var n := roundi((float(d.base) + float(d.per_danger) * float(danger)) * float(len_t) / 100.0)
	var kinds: Array = []
	var brutes := 0
	if danger >= int(d.brute_from) and n >= 6:
		brutes = 1 + (1 if n >= 16 else 0)
	var runners := 0
	if danger >= int(d.runner_from):
		runners = roundi(float(d.runner_share) * float(n))
	for i in n:
		if i < brutes:
			kinds.append("brute")
		elif i < brutes + runners:
			kinds.append("runner")
		else:
			kinds.append("walker")
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var keep := float(d.keep_from_start)
	var taken: Array = []
	var out: Array = []
	for kind in kinds:
		for attempt in 40:
			var s := rng.randf_range(keep + 2.0, float(len_t) - 2.0)
			var y := start_y + float(dir) * s
			var x := _c(geo, y) + rng.randf_range(-7.5, 7.5)
			var pos := Vector2(x, y)
			var tx := floori(x)
			var ty := floori(y)
			if not cv.is_open(tx, ty) or tx < 3 or tx >= cv.W - 3:
				continue
			if pos.distance_to(start) < keep + 1.0:
				continue
			var near := false
			for q in taken:
				if pos.distance_to(q) < 1.8:
					near = true
					break
			if near:
				continue
			if String(kind) == "brute":
				var roomy := true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if not cv.is_open(tx + dx, ty + dy):
							roomy = false
				if not roomy:
					continue
			taken.append(pos)
			out.append({"pos": pos, "kind": String(kind), "state": "still"})
			break
	var wanderers := maxi(1, roundi(float(d.wander_share) * float(out.size()))) if not out.is_empty() else 0
	for i in wanderers:
		out[i]["state"] = "wander"
	# (the first ones listed wander: the kinds were shuffled already)
	return out


# ---------------------------------------------------------------- passable --

## Whether a line `width` wide runs from the leg's start to its end: a breadth-first search over the lattice of tile corners (8
## neighbours), each point clear when no shut tile is nearer than width / 2 + 0.4 (the world's edge is shut). It is the proof the
## generator gives (a strip that fails is made again) and the test's. A 4-tile gap passes a car (2.6), 2 tiles a person (1.2).
static func passable(site: Dictionary, width: float) -> bool:
	var d: Dictionary = site.data
	var W := int(d.W)
	var H := int(d.H)
	var road: Dictionary = site.road
	var dir := int(road.dir)
	var solid := PackedByteArray()
	solid.resize(W * H)
	var src: Array = d.solidP
	for i in W * H:
		solid[i] = 1 if int(src[i]) != 0 else 0
	var r := width / 2.0 + 0.4
	var offs := _offsets_for(r)
	var LW := W + 1
	var blocked := PackedByteArray()
	blocked.resize(LW * (H + 1))
	for ty in H:
		for tx in W:
			if solid[ty * W + tx] == 0:
				continue
			# a tile buried among shut ones is covered by theirs
			if tx > 0 and tx < W - 1 and ty > 0 and ty < H - 1 and solid[ty * W + tx - 1] != 0 and solid[ty * W + tx + 1] != 0 and solid[(ty - 1) * W + tx] != 0 and solid[(ty + 1) * W + tx] != 0:
				continue
			for o in offs:
				var px: int = tx + o.x
				var py: int = ty + o.y
				if px >= 0 and px <= W and py >= 0 and py <= H:
					blocked[py * LW + px] = 1
	var edge := int(ceil(r - 0.0001))
	for py in H + 1:
		for px in edge:
			blocked[py * LW + px] = 1
			blocked[py * LW + W - px] = 1
	for px in LW:
		for py in edge:
			blocked[py * LW + px] = 1
			blocked[(H - py) * LW + px] = 1
	var start: Vector2 = road.start
	var end: Vector2 = road.end
	var sx := roundi(start.x)
	var sy := roundi(start.y)
	var ey := roundi(end.y)
	if blocked[sy * LW + sx] != 0:
		return false
	# a depth-first search that tries the way forward first: a clear strip is crossed in about its own length of steps
	var seen := PackedByteArray()
	seen.resize(LW * (H + 1))
	var stack := PackedInt32Array()
	stack.append(sy * LW + sx)
	seen[sy * LW + sx] = 1
	var order: Array = [Vector2i(0, dir), Vector2i(-1, dir), Vector2i(1, dir), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -dir), Vector2i(1, -dir), Vector2i(0, -dir)]
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		@warning_ignore("integer_division")
		var py: int = i / LW
		var px: int = i % LW
		if (py - ey) * dir >= 0:
			return true
		for k in range(order.size() - 1, -1, -1):
			var nx: int = px + order[k].x
			var ny: int = py + order[k].y
			if nx < 0 or nx > W or ny < 0 or ny > H:
				continue
			var j := ny * LW + nx
			if seen[j] == 0 and blocked[j] == 0:
				seen[j] = 1
				stack.append(j)
	return false


## The lattice offsets from a shut tile's corner (the tile spans 0 to 1) that lie nearer than r to the tile.
static func _offsets_for(r: float) -> Array:
	var key := "%.4f" % r
	if _offsets.has(key):
		return _offsets[key]
	var out: Array = []
	var span := int(ceil(r)) + 1
	for oy in range(-span, span + 2):
		for ox in range(-span, span + 2):
			var dx := 0.0
			if ox < 0:
				dx = float(-ox)
			elif ox > 1:
				dx = float(ox - 1)
			var dy := 0.0
			if oy < 0:
				dy = float(-oy)
			elif oy > 1:
				dy = float(oy - 1)
			if dx * dx + dy * dy < r * r - 0.000001:
				out.append(Vector2i(ox, oy))
	_offsets[key] = out
	return out
