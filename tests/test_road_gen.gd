extends "res://tests/case.gd"
## The road of the live drive (round 21, scripts/drive/road_gen.gd, assets/data/road_layouts.json): the strip of ground between
## the base and a place, made as a site `World.build` and `RaidRun` take as they take a place. These tests build roads with plans
## made by hand (the shape of `RoadEvents.plan`) and say: the same inputs give the same strip, both legs share the ground, the
## sizes, ends and exits are as the contract says, a car-wide (and a foot-wide) way always exists, every block has its gap and its
## solid wrecks, every stop has what it shows, the dead keep away from the start, the style follows the place, the budgets hold,
## and `SiteGen.map_data` is what the place's own site is made of.

const GD := preload("res://scripts/game_data.gd")
const Canvas := preload("res://scripts/raid/site_canvas.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")
const RoadGen := preload("res://scripts/drive/road_gen.gd")

const KINDS := ["sedan", "pickup", "van", "bus", ""]
const CRUISE := {"sedan": 7.68, "pickup": 7.04, "van": 7.04, "bus": 5.76, "": 3.2}
const EVENT_KIND := {"ambush": "dead", "roadblock": "block", "survivor": "stop", "wreck_supplies": "stop", "breakdown": "forced", "herd": "dead", "fuel_stash": "stop", "checkpoint": "stop", "smoke": "stop"}
const CAR_PROPS := ["car_h", "car_v", "car_police", "van_h", "pickup_v", "bus_h", "bus_v"]


func _places() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	return parsed.places


func _place(id: String) -> Dictionary:
	for p in _places():
		if String(p.id) == id:
			return p
	return {}


func _entry(i: int, id: String, at: float, seed_value: int = 1) -> Dictionary:
	return {"uid": "e%d" % (i + 1), "id": id, "kind": String(EVENT_KIND[id]), "at": at, "seed": seed_value, "night": false, "state": "pending", "def": {"title": id}}


## A hand-made plan of n events, spaced by 0.17 from 0.14 (inside [0.12, 0.9], 0.12 apart at least), the ids by the seed (never the
## same twice in a row).
func _plan(seed_value: int, n: int = 5, only: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var ids: Array = EVENT_KIND.keys()
	ids.sort()
	var out: Array = []
	var last := ""
	for i in n:
		var id := String(only[i % only.size()]) if not only.is_empty() else String(ids[rng.randi() % ids.size()])
		while id == last and only.size() <= 1 and ids.size() > 1:
			id = String(ids[rng.randi() % ids.size()])
		last = id
		var at := 0.14 + 0.17 * float(i) + rng.randf_range(-0.02, 0.02)
		if n == 1:
			at = 0.5
		out.append(_entry(i, id, clampf(at, 0.12, 0.9), seed_value + i))
	return out


func _ctx(kind: String, len_t: int, danger: int, plan: Array, hour: float = 10.0) -> Dictionary:
	var c := float(CRUISE[kind])
	return {"kind": kind, "road_min": float(len_t) / c, "cruise": c, "len": len_t, "plan": plan, "danger": danger, "hour": hour, "leg": "there"}


func _digest(site: Dictionary) -> int:
	var d: Dictionary = site.data
	return hash([d.terrain, d.solidP, d.objects, d.trees, d.marks, site.dead, site.road.slots, site.road.dyn, site.road.path, site.road.centerline])


func _solid_at(site: Dictionary, x: int, y: int) -> bool:
	var d: Dictionary = site.data
	if x < 0 or y < 0 or x >= int(d.W) or y >= int(d.H):
		return true
	return int(d.solidP[y * int(d.W) + x]) != 0


## The distance from a point to the nearest solid tile (a square), looked for within `reach` tiles; reach when none.
func _clearance(site: Dictionary, p: Vector2, reach: float = 4.0) -> float:
	var best := reach
	for ty in range(floori(p.y - reach), floori(p.y + reach) + 1):
		for tx in range(floori(p.x - reach), floori(p.x + reach) + 1):
			if not _solid_at(site, tx, ty):
				continue
			var dx := maxf(maxf(float(tx) - p.x, p.x - float(tx + 1)), 0.0)
			var dy := maxf(maxf(float(ty) - p.y, p.y - float(ty + 1)), 0.0)
			best = minf(best, sqrt(dx * dx + dy * dy))
	return best


func _slot(site: Dictionary, uid: String) -> Dictionary:
	for s in site.road.slots:
		if String(s.uid) == uid:
			return s
	return {}


# ------------------------------------------------------------------- the data --

func test_the_layouts_file_has_the_styles_and_the_geometry() -> void:
	var lay := RoadGen.layouts()
	check(not lay.is_empty(), "road_layouts.json loads")
	for k in ["geometry", "styles", "wrecks", "block", "dead"]:
		check(lay.has(k), "road_layouts.json has %s" % k)
	for s in ["urban", "rural", "industrial"]:
		check(lay.styles.has(s), "style %s" % s)
		var st: Dictionary = lay.styles.get(s, {})
		for k in ["kinds", "carriage", "verge", "ground"]:
			check(st.has(k), "style %s has %s" % [s, k])
	var covered := {}
	for p in _places():
		covered[String(p.kind)] = true
	for kind in covered:
		var style := RoadGen.style_of({"kind": kind})
		check(style in ["urban", "rural", "industrial"], "the kind %s has a style" % kind)


func test_the_style_follows_the_place_kind() -> void:
	eq(RoadGen.style_of(_place("farm_a")), "rural", "a farm")
	eq(RoadGen.style_of(_place("water_works")), "rural", "the water works")
	eq(RoadGen.style_of(_place("checkpoint")), "rural", "the checkpoint")
	eq(RoadGen.style_of(_place("scrapyard")), "industrial", "the scrapyard")
	eq(RoadGen.style_of(_place("warehouse")), "industrial", "the warehouse")
	eq(RoadGen.style_of(_place("power_station")), "industrial", "the power station")
	eq(RoadGen.style_of(_place("pharmacy")), "urban", "the pharmacy")
	eq(RoadGen.style_of(_place("houses")), "urban", "the houses")
	eq(RoadGen.style_of({"kind": "no_such_kind"}), "urban", "an unknown kind is urban")
	var rural := RoadGen.make(_place("farm_a"), 4, "there", _ctx("pickup", 240, 1, []))
	var urban := RoadGen.make(_place("pharmacy"), 4, "there", _ctx("pickup", 240, 1, []))
	var industrial := RoadGen.make(_place("scrapyard"), 4, "there", _ctx("pickup", 240, 1, []))
	eq(rural.road.style, "rural")
	eq(urban.road.style, "urban")
	eq(industrial.road.style, "industrial")
	# the verge beside the carriageway is the style's own ground
	var tid := {"SIDEWALK": 2, "DIRT": 13}
	for pair in [[urban, "SIDEWALK"], [rural, "DIRT"], [industrial, "DIRT"]]:
		var site: Dictionary = pair[0]
		var W := int(site.data.W)
		var y := int(site.road.start.y) - 30
		var found := false
		for x in W:
			if int(site.data.terrain[y * W + x]) == int(tid[pair[1]]):
				found = true
		check(found, "%s verge is %s" % [site.road.style, pair[1]])


# ------------------------------------------------------------ determinism, shape --

func test_the_same_inputs_make_the_same_strip_and_another_seed_a_different_one() -> void:
	var place := _place("pharmacy")
	var plan := _plan(5)
	var a := RoadGen.make(place, 11, "there", _ctx("pickup", 260, 2, plan))
	var b := RoadGen.make(place, 11, "there", _ctx("pickup", 260, 2, plan))
	var c := RoadGen.make(place, 12, "there", _ctx("pickup", 260, 2, plan))
	eq(_digest(a), _digest(b), "the same inputs, the same strip")
	check(_digest(a) != _digest(c), "another seed, another strip")
	var home_a := RoadGen.make(place, 11, "home", _ctx("pickup", 260, 2, plan))
	var home_b := RoadGen.make(place, 11, "home", _ctx("pickup", 260, 2, plan))
	eq(_digest(home_a), _digest(home_b), "the same inputs, the same strip, home too")


func test_both_legs_share_the_ground() -> void:
	var place := _place("police")
	var there_plan := _plan(2, 4)
	var home_plan := _plan(9, 3)
	var there := RoadGen.make(place, 21, "there", _ctx("van", 300, 3, there_plan))
	var home := RoadGen.make(place, 21, "home", _ctx("van", 300, 3, home_plan))
	eq(there.data.terrain, home.data.terrain, "the same ground tiles")
	eq(there.data.marks, home.data.marks, "the same road markings")
	eq(there.size, home.size, "the same size")
	eq(there.road.style, home.road.style, "the same style")
	eq(there.road.len, home.road.len, "the same length")
	var n: int = there.road.centerline.size()
	eq(home.road.centerline.size(), n, "the centre line has the same points")
	var same := true
	for i in n:
		if there.road.centerline[i].distance_to(home.road.centerline[n - 1 - i]) > 0.0001:
			same = false
	check(same, "the centre line of the way home is the way there's turned round")
	eq(there.road.end, home.road.start, "the place's mouth is where the way home begins")
	eq(there.road.start, home.road.end, "the base's end is where the way home ends")
	# with no events the two legs are the same ground, objects and all (the dead and the events are the leg's own)
	var bare_there := RoadGen.make(place, 21, "there", _ctx("van", 300, 3, []))
	var bare_home := RoadGen.make(place, 21, "home", _ctx("van", 300, 3, []))
	eq(bare_there.data.objects, bare_home.data.objects, "the same props")
	eq(bare_there.data.trees, bare_home.data.trees, "the same trees")
	eq(bare_there.data.solidP, bare_home.data.solidP, "the same solid ground")


func test_the_strip_is_30_wide_and_len_plus_24_tall() -> void:
	var place := _place("pharmacy")
	for pair in [["sedan", 231], ["pickup", 211], ["bus", 174], ["", 96], ["", 288]]:
		var kind := String(pair[0])
		var len_t := int(pair[1])
		var site := RoadGen.make(place, 3, "there", _ctx(kind, len_t, 2, _plan(3, 3)))
		eq(site.size, Vector2i(30, len_t + 24), "size for %s %d" % [kind, len_t])
		eq(int(site.data.W), 30)
		eq(int(site.data.H), len_t + 24)
		eq(site.data.terrain.size(), 30 * (len_t + 24), "the terrain covers the strip")
		eq(site.data.solidP.size(), 30 * (len_t + 24), "the solid grid covers the strip")
		eq(site.data.solidZ.size(), 30 * (len_t + 24), "the other solid grid too")
		eq(site.kind, "road")
		eq(site.name, "The road to The pharmacy")
		eq(site.vehicle_spot, Vector2(-1, -1))
		eq(site.containers, [])
		eq(site.rooms, [])
		eq(site.seed, 3)
		eq(site.danger, 2)
		eq(int(site.road.width), 30)
		check(absf(float(site.road.start.y) - float(site.road.end.y)) == float(len_t), "start and end are len rows apart (%d)" % len_t)
		check(float(site.road.len) >= float(len_t) and float(site.road.len) < float(len_t) * 1.06, "road.len is the centre line's own length")


func test_len_is_made_from_the_road_minutes_when_the_context_has_none() -> void:
	var ctx := _ctx("pickup", 0, 1, [])
	ctx.erase("len")
	ctx["road_min"] = 80.0
	ctx["cruise"] = 7.0
	var site := RoadGen.make(_place("pharmacy"), 2, "there", ctx)
	eq(site.size, Vector2i(30, 560 + 24), "80 minutes at 7 tiles/s is 80 s: 560 tiles")
	ctx["road_min"] = 400.0
	ctx["cruise"] = 9.0
	var long_site := RoadGen.make(_place("pharmacy"), 2, "there", ctx)
	eq(long_site.size, Vector2i(30, RoadGen.MAX_STRIP + 24), "never longer than the strip's cap")


func test_the_ends_the_entry_and_the_exit_follow_the_leg() -> void:
	var place := _place("pharmacy")
	var there := RoadGen.make(place, 8, "there", _ctx("pickup", 200, 1, []))
	var home := RoadGen.make(place, 8, "home", _ctx("pickup", 200, 1, []))
	eq(int(there.road.dir), -1, "the way there runs north")
	eq(int(home.road.dir), 1, "the way home runs south")
	eq(String(there.road.leg), "there")
	eq(String(home.road.leg), "home")
	check(there.road.start.y > there.road.end.y, "there: start south of end")
	check(home.road.start.y < home.road.end.y, "home: start north of end")
	check(there.road.start.y >= float(there.size.y) - 12.5, "there starts at the base's end of the strip")
	for site in [there, home]:
		var W := int(site.data.W)
		var st: Vector2 = site.road.start
		var en: Vector2 = site.road.end
		eq(site.entry, st, "the entry is the leg's start")
		# the start and the end are on the carriageway
		eq(int(site.data.terrain[int(st.y) * W + int(st.x)]), 1, "the start is on the asphalt")
		eq(int(site.data.terrain[int(en.y) * W + int(en.x)]), 1, "the end is on the asphalt")
		# the exit: the last 6 rows of the leg, the whole width
		var ex: Rect2 = site.exit
		eq(ex.size, Vector2(30, 6), "the exit is 6 rows of the whole width")
		eq(ex.position.x, 0.0)
		var d := int(site.road.dir)
		if d < 0:
			eq(ex.end.y, en.y, "north: the exit ends where the road does")
		else:
			eq(ex.position.y, en.y, "south: the exit begins where the road ends")
		check(not ex.has_point(st), "the start is not in the exit")
		check(ex.position.y >= 0.0 and ex.end.y <= float(site.size.y), "the exit is inside the strip")
	eq(there.road.centerline[0], there.road.start, "the centre line begins at the start")
	eq(there.road.centerline[there.road.centerline.size() - 1], there.road.end, "and ends at the end")
	eq(home.road.centerline[0], home.road.start)
	eq(home.road.path[0], home.road.start, "the path begins at the start")
	eq(home.road.path[home.road.path.size() - 1], home.road.end, "and ends at the end")


func test_the_centre_line_winds_gently_and_the_path_follows_it() -> void:
	var site := RoadGen.make(_place("pharmacy"), 31, "there", _ctx("sedan", 400, 1, _plan(4, 3)))
	var cl: PackedVector2Array = site.road.centerline
	var path: PackedVector2Array = site.road.path
	var dir := float(site.road.dir)
	var max_slope := 0.0
	var arc := 0.0
	for i in range(1, cl.size()):
		var step := cl[i] - cl[i - 1]
		check(step.y * dir > 0.0, "the centre line only moves forward (point %d)" % i)
		max_slope = maxf(max_slope, absf(step.x / step.y))
		arc += step.length()
	check(max_slope <= 0.2501, "|dx/dy| of the centre line is at most 0.25 (%f)" % max_slope)
	check(absf(arc - float(site.road.len)) < 0.01, "road.len is the arc length of the centre line")
	var worst := 0.0
	var gap_max := 0.0
	for i in path.size():
		if i > 0:
			check((path[i].y - path[i - 1].y) * dir > 0.0, "the path only moves forward (point %d)" % i)
			gap_max = maxf(gap_max, path[i].distance_to(path[i - 1]))
		if _clearance(site, path[i], 1.4) < 1.3:
			worst += 1.0
	check(gap_max <= 2.0, "the path's points are close enough to follow (%f)" % gap_max)
	eq(worst, 0.0, "the path keeps 1.3 tiles from every solid tile (a bus is 2.6 wide)")


func test_the_lane_marks_follow_the_centre_and_the_path_keeps_to_the_asphalt() -> void:
	var site := RoadGen.make(_place("pharmacy"), 31, "there", _ctx("sedan", 400, 1, _plan(4, 3)))
	var marks: Array = site.data.marks
	check(marks.size() > 20, "the road has painted lines (%d pieces)" % marks.size())
	var cl: PackedVector2Array = site.road.centerline
	var top := cl[cl.size() - 1].y
	var bottom := cl[0].y
	for m in marks:
		eq(String(m.kind), "lanes")
		eq(String(m.dir), "v", "the lines run down the strip")
		var y := float(m.cy)
		if y < top - 12.0 or y > bottom + 12.0:
			continue
		var i := clampi(int(round(bottom - y)), 0, cl.size() - 1)
		check(absf(float(m.cx) - cl[i].x) < 0.6, "a piece of line at row %.1f is on the centre (%f against %f)" % [y, m.cx, cl[i].x])
	var W := int(site.data.W)
	for p in site.road.path:
		eq(int(site.data.terrain[int(p.y) * W + int(p.x)]), 1, "the path is on the asphalt at (%.1f, %.1f)" % [p.x, p.y])


func test_nothing_stands_in_the_road_but_what_the_plan_puts_there() -> void:
	for pair in [["pharmacy", 3], ["farm_a", 3], ["scrapyard", 3]]:
		var site := RoadGen.make(_place(String(pair[0])), 41, "there", _ctx("pickup", 400, int(pair[1]), []))
		var worst := 9.0
		for p in site.road.centerline:
			worst = minf(worst, _clearance(site, p, 4.0))
		check(worst >= 2.4, "%s: the centre line keeps %f from every solid tile" % [pair[0], worst])


# ------------------------------------------------------------------ passable --

func test_a_car_wide_way_exists_over_many_strips() -> void:
	var places := _places()
	var bad: Array = []
	var kinds_seen := {}
	for i in 300:
		var place: Dictionary = places[i % places.size()]
		var kind := String(KINDS[(i * 3) % KINDS.size()])
		var danger := floori(float(i) / 3.0) % 4
		var leg := "there" if i % 2 == 0 else "home"
		var len_t := 96 + (i * 37) % 160 if kind == "" else 174 + (i * 37) % 120
		var plan := _plan(i, 5)
		var site := RoadGen.make(place, i + 1, leg, _ctx(kind, len_t, danger, plan))
		kinds_seen[String(place.kind)] = true
		var w := 1.2 if kind == "" else 2.6
		if not RoadGen.passable(site, w):
			bad.append("%s seed %d %s %s d%d len %d" % [place.id, i + 1, leg, kind, danger, len_t])
		if kind != "" and not RoadGen.passable(site, 1.2):
			bad.append("narrow %s seed %d" % [place.id, i + 1])
	eq(bad, [], "every strip has a way through")
	check(kinds_seen.size() >= 20, "the strips cover the kinds of places (%d)" % kinds_seen.size())


func test_a_full_length_road_is_passable_for_a_car_and_on_foot() -> void:
	for pair in [["pharmacy", "pickup", 3], ["scrapyard", "bus", 3], ["farm_a", "", 1]]:
		var place := _place(String(pair[0]))
		var kind := String(pair[1])
		var len_t := RoadGen.MAX_STRIP
		var plan := _plan(17, 5)
		var site := RoadGen.make(place, 77, "there", _ctx(kind, len_t, int(pair[2]), plan))
		eq(site.size, Vector2i(30, RoadGen.MAX_STRIP + 24))
		check(RoadGen.passable(site, 2.6 if kind != "" else 1.2), "%s full length is passable" % pair[0])


func test_passable_is_false_for_a_strip_shut_across() -> void:
	var site := RoadGen.make(_place("pharmacy"), 5, "there", _ctx("pickup", 200, 1, []))
	check(RoadGen.passable(site, 2.6), "the open strip is passable")
	var d: Dictionary = site.data
	var W := int(d.W)
	var shut: Array = d.solidP.duplicate()
	var y := int(site.road.start.y) - 100
	for x in W:
		shut[y * W + x] = 1
		shut[(y + 1) * W + x] = 1
	var d2 := d.duplicate(false)
	d2["solidP"] = shut
	var s2 := site.duplicate(false)
	s2["data"] = d2
	check(not RoadGen.passable(s2, 2.6), "a wall across the whole width stops it")
	check(not RoadGen.passable(s2, 1.2), "and a person too")


func test_a_gap_a_person_fits_is_not_a_gap_a_car_fits() -> void:
	# a wall with one opening: 2 tiles let a person (1.2) through and not a car (2.6); 4 let a car through
	var site := RoadGen.make(_place("pharmacy"), 5, "there", _ctx("pickup", 200, 1, []))
	var d: Dictionary = site.data
	var W := int(d.W)
	var y := int(site.road.start.y) - 100
	var cx := int(site.road.centerline[100].x)
	for gap_w in [2, 3, 4]:
		var shut: Array = d.solidP.duplicate()
		for row in 3:
			for x in W:
				if x < cx - 1 or x >= cx - 1 + gap_w:
					shut[(y + row) * W + x] = 1
		var d2 := d.duplicate(false)
		d2["solidP"] = shut
		var s2 := site.duplicate(false)
		s2["data"] = d2
		check(RoadGen.passable(s2, 1.2) == (gap_w >= 2), "a person through %d tiles" % gap_w)
		check(RoadGen.passable(s2, 2.6) == (gap_w >= 4), "a car through %d tiles" % gap_w)


# ---------------------------------------------------------------- the events --

func test_every_plan_entry_has_its_slot() -> void:
	var plan := _plan(6, 5)
	var site := RoadGen.make(_place("hospital"), 3, "there", _ctx("pickup", 300, 2, plan))
	eq(site.road.slots.size(), plan.size(), "one slot for each entry")
	var last_y := 1.0e9
	for i in plan.size():
		var e: Dictionary = plan[i]
		var s: Dictionary = site.road.slots[i]
		eq(String(s.uid), String(e.uid))
		eq(String(s.id), String(e.id))
		for k in ["anchor", "y", "gap", "spawn", "figure"]:
			check(s.has(k), "slot has %s" % k)
		check(s.anchor is Vector2 and s.spawn is Vector2, "anchor and spawn are points")
		check(float(s.y) <= last_y, "the slots follow the way there, north")
		last_y = float(s.y)
		# near the share of the road the plan asked for (the road's length from the start)
		var share := (float(site.road.start.y) - float(s.y)) / float(site.road.len)
		check(absf(share - float(e.at)) < 0.06, "slot %s is near its share (%f against %f)" % [e.uid, share, e.at])
		var W := int(site.data.W)
		var a: Vector2 = s.anchor
		eq(int(site.data.terrain[int(a.y) * W + int(a.x)]), 1, "the anchor is on the asphalt")
		if EVENT_KIND[e.id] == "block":
			check(s.gap is Rect2, "a block has its gap")
		else:
			check(s.gap == null, "only a block has a gap")


func test_the_way_home_has_its_slots_going_south() -> void:
	var plan := _plan(8, 4)
	var site := RoadGen.make(_place("pharmacy"), 9, "home", _ctx("sedan", 250, 1, plan))
	var last_y := -1.0
	for s in site.road.slots:
		check(float(s.y) >= last_y, "the slots follow the way home, south")
		last_y = float(s.y)


func test_each_block_has_its_gap_and_its_solid_wrecks() -> void:
	for kind in ["pickup", "bus", ""]:
		for seed_value in [1, 2, 3, 4, 5, 6]:
			var plan := [_entry(0, "roadblock", 0.3, seed_value), _entry(1, "smoke", 0.5), _entry(2, "roadblock", 0.75, seed_value + 1)]
			var site := RoadGen.make(_place("pharmacy"), seed_value, "there" if seed_value % 2 == 0 else "home", _ctx(kind, 240, 2, plan))
			var d: Dictionary = site.data
			var W := int(d.W)
			var need := 1.4 if kind == "" else 3.4
			for uid in ["e1", "e3"]:
				var s := _slot(site, uid)
				check(s.gap is Rect2, "block %s has a gap" % uid)
				if not (s.gap is Rect2):
					continue
				var gap: Rect2 = s.gap
				check(gap.size.x >= need, "the gap of %s is %f wide, %f needed (%s)" % [uid, gap.size.x, need, kind])
				# the gap is open ground
				for ty in range(int(gap.position.y), int(gap.end.y)):
					for tx in range(int(gap.position.x), int(gap.end.x)):
						check(not _solid_at(site, tx, ty), "the gap tile (%d, %d) is open" % [tx, ty])
				# the path goes through its middle
				var through := false
				for p in site.road.path:
					if absf(p.y - float(s.y)) < 1.0 and p.x > gap.position.x and p.x < gap.end.x:
						through = true
				check(through, "the path goes through the gap of %s" % uid)
				# the line across the carriageway is whole but for the gap
				var row := int(s.y)
				var open_asphalt := 0
				for x in range(2, W - 2):
					if x >= int(gap.position.x) and x < int(gap.end.x):
						continue
					if not _solid_at(site, x, row):
						open_asphalt += 1
				eq(open_asphalt, 0, "the line of %s is shut but for the gap (row %d)" % [uid, row])
	# the wrecks
	var plan2 := [_entry(0, "roadblock", 0.4, 3)]
	var site2 := RoadGen.make(_place("pharmacy"), 3, "there", _ctx("pickup", 240, 2, plan2))
	var dyn: Array = site2.road.dyn
	check(dyn.size() >= 2 and dyn.size() <= 6, "a block's wrecks are listed (%d)" % dyn.size())
	var seen_tiles := {}
	for w in dyn:
		for k in ["id", "file", "pos", "rot", "size", "tiles", "ram_hp"]:
			check(w.has(k), "a wreck has %s" % k)
		check(ResourceLoader.exists(String(w.file)), "the wreck's picture exists: %s" % w.file)
		check(w.pos is Vector2 and w.size is Vector2, "pos and size are points")
		check(Vector2(w.size).x > 0.5 and Vector2(w.size).y > 0.5, "the wreck is drawn at a size")
		check(float(w.ram_hp) in [8.0, 15.0], "a car costs 8 hp to ram, a bus 15")
		check(w.tiles.size() >= 2, "the wreck covers tiles")
		for idx in w.tiles:
			eq(int(site2.data.solidP[int(idx)]), 1, "a wreck's tile is solid in the grid")
			eq(int(site2.data.solidZ[int(idx)]), 1, "and in the other grid")
			check(not seen_tiles.has(int(idx)), "no tile belongs to two wrecks")
			seen_tiles[int(idx)] = true
		# a wreck is drawn by the scene: it is not among the map's own objects
		for o in site2.data.objects:
			for pc in o.pieces:
				check(not (String(pc.file) == String(w.file) and absf(float(pc.x) + float(pc.w) / 2.0 - float(w.pos.x)) < 0.4 and absf(float(pc.y) + float(pc.h) / 2.0 - float(w.pos.y)) < 0.4), "the wreck is not also a map object")
	# the wrecks are what shuts the line across the carriageway: with them gone the carriageway is clear
	var s2 := _slot(site2, "e1")
	var row2 := int(s2.y)
	var W2 := int(site2.data.W)
	for w in dyn:
		for idx in w.tiles:
			site2.data.solidP[int(idx)] = 0
	var carriageway_shut := 0
	for x in W2:
		if int(site2.data.terrain[row2 * W2 + x]) == 1 and _solid_at(site2, x, row2):
			carriageway_shut += 1
	eq(carriageway_shut, 0, "with the wrecks gone the whole carriageway is open (Clear it)")


func test_a_road_with_two_blocks_keeps_to_eight_wrecks() -> void:
	var plan := [_entry(0, "roadblock", 0.25, 1), _entry(1, "roadblock", 0.6, 2), _entry(2, "roadblock", 0.85, 3)]
	for kind in ["sedan", ""]:
		var site := RoadGen.make(_place("pharmacy"), 12, "there", _ctx(kind, 400, 3, plan))
		check(site.road.dyn.size() <= 8, "at most 8 wrecks (%d)" % site.road.dyn.size())
		check(RoadGen.passable(site, 2.6 if kind != "" else 1.2), "three blocks and still a way (%s)" % kind)


func test_every_stop_shows_what_it_is() -> void:
	var ids := ["survivor", "wreck_supplies", "fuel_stash", "checkpoint", "smoke"]
	for seed_value in [1, 2, 3, 4]:
		var plan: Array = []
		for i in ids.size():
			plan.append(_entry(i, String(ids[i]), 0.14 + 0.17 * float(i), seed_value))
		var site := RoadGen.make(_place("pharmacy"), seed_value, "there" if seed_value < 3 else "home", _ctx("pickup", 330, 2, plan))
		for i in ids.size():
			var s := _slot(site, "e%d" % (i + 1))
			var id := String(ids[i])
			var props: Array = s.get("props", [])
			check(s.figure != null or not props.is_empty(), "%s shows a figure or props" % id)
			if id == "survivor":
				check(s.figure is Vector2, "the survivor is a person at figure")
			if id == "checkpoint":
				check(s.get("figures", []).size() == 2, "the checkpoint has two figures")
				check(s.figure is Vector2, "and the first is `figure`")
			if id == "fuel_stash":
				check(props.size() >= 3, "drums and a cab (%d)" % props.size())
			# the figure stands on the verge, within reach of the road
			if s.figure is Vector2:
				var f: Vector2 = s.figure
				var a: Vector2 = s.anchor
				check(f.distance_to(a) < 9.0, "the figure is near the road (%f)" % f.distance_to(a))
				check(not _solid_at(site, int(f.x), int(f.y)), "the figure stands on open ground")
			# every prop it lists is on the map
			for pr in props:
				var found := false
				for o in site.data.objects:
					if String(o.kind) == String(pr.kind) and Vector2(float(o.cx), float(o.cy)).distance_to(Vector2(pr.pos)) < 0.7:
						found = true
				check(found, "%s: the prop %s at %s is on the map" % [id, pr.kind, str(pr.pos)])
	check(RoadGen.passable(RoadGen.make(_place("pharmacy"), 1, "there", _ctx("pickup", 330, 2, [_entry(0, "checkpoint", 0.5, 1), _entry(1, "fuel_stash", 0.8, 2)])), 2.6), "stops leave the road open")


func test_the_dead_ahead_and_forced_events_keep_their_stretch() -> void:
	var plan := [_entry(0, "ambush", 0.3), _entry(1, "breakdown", 0.5), _entry(2, "herd", 0.75)]
	var site := RoadGen.make(_place("pharmacy"), 14, "there", _ctx("pickup", 300, 2, plan))
	for uid in ["e1", "e3"]:
		var s := _slot(site, uid)
		check(s.spawn is Vector2, "a dead stretch has its spawn")
		var sp: Vector2 = s.spawn
		check(absf(sp.y - float(s.y)) < 1.0, "the spawn is on the stretch")
		# the road about it is clear of solid props (the dead are poured onto it)
		for dy in range(-8, 9):
			var row := int(sp.y) + dy
			var W := int(site.data.W)
			for x in W:
				if int(site.data.terrain[row * W + x]) == 1:
					check(not _solid_at(site, x, row), "the stretch of %s is clear" % uid)
	var forced := _slot(site, "e2")
	check(forced.gap == null and forced.figure == null, "a puncture asks for nothing on the map")


func test_the_last_resort_has_no_wrecks_and_still_a_way() -> void:
	# a strip that failed its proof five times would be made without the blocks' wrecks: the same road, nothing across it
	var plan := [_entry(0, "roadblock", 0.3, 1), _entry(1, "roadblock", 0.7, 2)]
	var ctx := _ctx("pickup", 240, 2, plan)
	var site := RoadGen._build(_place("pharmacy"), 3, "there", ctx, 0, true)
	eq(site.road.dyn, [], "no wrecks listed")
	check(RoadGen.passable(site, 2.6), "and a way through")
	for s in site.road.slots:
		check(s.gap is Rect2, "the slots keep their gaps")


# ---------------------------------------------------------------- the dead --

func test_no_dead_within_20_tiles_of_the_start_and_the_count_follows_danger() -> void:
	for danger in 4:
		for len_t in [200, 400]:
			var site := RoadGen.make(_place("police"), 6 + danger, "there", _ctx("pickup", len_t, danger, []))
			var want := roundi(float(2 + 2 * danger) * float(len_t) / 100.0)
			check(absi(site.dead.size() - want) <= 1, "danger %d len %d: %d dead, %d wanted" % [danger, len_t, site.dead.size(), want])
			var kinds := {}
			for z in site.dead:
				check(Vector2(z.pos).distance_to(site.road.start) >= 20.0, "a dead one is %f from the start" % Vector2(z.pos).distance_to(site.road.start))
				check(z.state in ["still", "wander"], "state %s" % z.state)
				check(z.kind in ["walker", "runner", "brute"], "kind %s" % z.kind)
				check(not _solid_at(site, int(z.pos.x), int(z.pos.y)), "a dead one stands on open ground")
				kinds[z.kind] = true
			if danger < 2:
				check(not kinds.has("runner"), "no runners below danger 2")
			if danger < 3:
				check(not kinds.has("brute"), "no brutes below danger 3")
	var home := RoadGen.make(_place("police"), 6, "home", _ctx("pickup", 300, 2, []))
	for z in home.dead:
		check(Vector2(z.pos).distance_to(home.road.start) >= 20.0, "home: a dead one keeps off the start")
	var there := RoadGen.make(_place("police"), 6, "there", _ctx("pickup", 300, 2, []))
	check(hash(there.dead) != hash(home.dead), "the dead of the way home are new")


func test_wrecks_scale_with_danger() -> void:
	var counts: Array = []
	for danger in [0, 3]:
		var site := RoadGen.make(_place("pharmacy"), 5, "there", _ctx("pickup", 300, danger, []))
		var n := 0
		for o in site.data.objects:
			if String(o.kind) in CAR_PROPS:
				n += 1
		counts.append(n)
	check(counts[1] >= counts[0] + 8, "more wrecks at danger 3 than at 0 (%d against %d)" % [counts[1], counts[0]])
	check(counts[0] >= 3, "even a safe road has a few (%d)" % counts[0])


func test_the_ambient_night_road_is_carried_in_the_road() -> void:
	var ctx := _ctx("pickup", 200, 1, [])
	var amb := [{"id": "night_road", "dead_mult": 1.5, "runner_share": 0.15, "headlights": true}]
	ctx["ambient"] = amb
	var site := RoadGen.make(_place("pharmacy"), 2, "home", ctx)
	eq(site.road.ambient, amb, "the context's ambient is the road's")
	var plain := RoadGen.make(_place("pharmacy"), 2, "home", _ctx("pickup", 200, 1, []))
	check(plain.road.ambient is Array, "with none given it is a list")


# ------------------------------------------------------------------ budgets --

func test_the_budgets_hold_for_the_longest_dangerous_road() -> void:
	var plan := [_entry(0, "roadblock", 0.14), _entry(1, "survivor", 0.31), _entry(2, "roadblock", 0.48), _entry(3, "checkpoint", 0.65), _entry(4, "fuel_stash", 0.82)]
	var t0 := Time.get_ticks_msec()
	var site := RoadGen.make(_place("scrapyard"), 3, "there", _ctx("sedan", RoadGen.MAX_STRIP, 3, plan))
	var ms := Time.get_ticks_msec() - t0
	var tiles := int(site.data.W) * int(site.data.H)
	check(tiles <= 30 * (RoadGen.MAX_STRIP + 24), "tiles %d" % tiles)
	check(site.data.objects.size() <= 350, "objects %d" % site.data.objects.size())
	check(site.data.objects.size() + site.data.trees.size() <= 350, "objects and trees %d" % (site.data.objects.size() + site.data.trees.size()))
	check(site.road.dyn.size() <= 8, "wrecks %d" % site.road.dyn.size())
	check(ms < 8000, "the longest strip is made in %d ms" % ms)
	print("        (the longest strip: %d ms, %d objects, %d trees, %d dead, %d wrecks)" % [ms, site.data.objects.size(), site.data.trees.size(), site.dead.size(), site.road.dyn.size()])
	var t1 := Time.get_ticks_msec()
	var ok := RoadGen.passable(site, 2.6)
	print("        (passable: %s in %d ms)" % [str(ok), Time.get_ticks_msec() - t1])
	check(ok, "and it has a way through")


# -------------------------------------------------------------- map_data ---

func test_map_data_is_what_the_place_sites_are_made_of() -> void:
	var place := _place("pharmacy")
	var seed_value := 3
	var site := SiteGen.make(place, seed_value, 3, false)
	# the same canvas as `SiteGen.make` draws, by hand, and the map made of it
	var lay := SiteGen.layouts()
	var recipe: Dictionary = lay.recipes[SiteGen.recipe_name(place)]
	var W := int(recipe.size[0])
	var H := int(recipe.size[1])
	var base := GD.load_all()
	var terrain_types: Dictionary = base.terrainTypes.duplicate(true)
	for k in lay.terrain:
		terrain_types[k] = {"id": int(lay.terrain[k].id), "file": String(lay.terrain[k].file)}
	var tids := {}
	for k in terrain_types:
		tids[k] = int(terrain_types[k].id)
	var key := SiteGen._hash("%s|%d" % [String(place.id), seed_value])
	var cv := Canvas.new()
	cv.setup(W, H, key, lay.props, tids, lay.get("templates", {}))
	cv.danger = int(place.get("danger", 1))
	cv.flags = {"vehicle": String(place.get("vehicle", "")) != "", "nest": place.get("nest") is Dictionary and int(place.nest.get("strength", 0)) > 0, "survivor": bool(place.get("survivor", false))}
	cv.run(recipe)
	if bool(recipe.get("mirror", true)) and (SiteGen._hash("mirror|%d" % key) & 1) == 1:
		cv.mirror()
	var rooms_dict := {}
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var r: Rect2i = a.rect
		var nm := String(a.name)
		var n := 2
		while rooms_dict.has(nm):
			nm = "%s_%d" % [String(a.name), n]
			n += 1
		rooms_dict[nm] = [r.position.x, r.position.y, r.end.x, r.end.y]
	var entry := Vector2(float(cv.entry.x) + 0.5, float(cv.entry.y) + 0.5)
	var data := SiteGen.map_data(cv, entry, rooms_dict)
	for k in ["W", "H", "terrain", "solidZ", "solidP", "wall", "objects", "marks", "walls", "segments", "trees", "lights", "rooms", "spawns", "yard", "workshop", "people", "bonds", "terrainTypes"]:
		eq(data.get(k), site.data.get(k), "map_data's %s is the site's" % k)
	check(data.has("weapons") and data.has("guns"), "the base data comes with it")


# ----------------------------------------------------- the events' own module --

func test_roads_for_the_plans_road_events_makes() -> void:
	if not ResourceLoader.exists("res://scripts/drive/road_events.gd"):
		return
	var events = load("res://scripts/drive/road_events.gd")
	var places := _places()
	var bad: Array = []
	var total := 0
	for i in 40:
		var place: Dictionary = places[(i * 5) % places.size()]
		var kind := String(KINDS[i % KINDS.size()])
		var danger := i % 4
		var len_t := 180 + (i * 29) % 300 if kind != "" else 100 + (i * 29) % 200
		var leg := "home" if i % 3 == 0 else "there"
		var ectx := {"leg": leg, "danger": danger, "by_vehicle": kind != "", "seats_free": 1, "seats": 3, "road_min": float(len_t) / float(CRUISE[kind]), "hour": 9.0 + float(i % 12), "bed": true, "hp_share": 0.8, "fuel_room": 4.0, "stock": {"scrap": 30, "food": 20}, "leading": 2, "building": 2, "caller": "x"}
		var plan: Array = events.plan(i + 1, ectx)
		var ctx := ectx.duplicate()
		ctx["kind"] = kind
		ctx["cruise"] = float(CRUISE[kind])
		ctx["len"] = len_t
		ctx["plan"] = plan
		var site := RoadGen.make(place, i + 11, leg, ctx)
		total += plan.size()
		eq(site.road.slots.size(), plan.size(), "a slot for each of the events' entries")
		eq(site.road.ambient, events.ambient_for(ctx), "the night road is the events' own")
		if not RoadGen.passable(site, 2.6 if kind != "" else 1.2):
			bad.append("%s %d %s" % [place.id, i, leg])
		for s in site.road.slots:
			if s.gap is Rect2:
				check(s.gap.size.x >= (3.4 if kind != "" else 1.4), "the gap fits the walker")
	eq(bad, [], "every road for a real plan has a way through")
	check(total >= 40, "the plans had events (%d)" % total)
