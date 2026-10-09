## The plan lab (WORLD3): builds every PLAN of scripts/town/building_recipes.gd in many random lots and checks what the generator must keep (every room reached from the way in, every container
## reachable, a door out, the walls inside the lot, rooms of a size), then draws one of each as a CATALOGUE SHEET.
##
##   godot --headless --path . --script res://tools/plan_lab.gd -- [--trials=40] [--only=ranch,duplex] [--seed=1] [--sheet=/tmp/catalogue.png] [--ts=10] [--quiet]
##
## The sheet is a picture of the plans (floors, walls, doors, furniture) with the roof of each (its style, its colour, the porch, the awning, the canopy and the sign) over it, a name under each
## one: the BUILDING CATALOGUE. Without a window: a headless run draws it too.
extends SceneTree

const GD := preload("res://scripts/game_data.gd")
const TownKit := preload("res://scripts/town/town_kit.gd")
const BuildingGen := preload("res://scripts/town/building_gen.gd")
const Plans := preload("res://scripts/town/building_plans.gd")
const Recipes := preload("res://scripts/town/building_recipes.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")

const GLYPHS := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110", "E": "111100110100111", "F": "111100110100100",
	"G": "011100101101011", "H": "101101111101101", "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100", "Q": "010101101110011", "R": "110101110101101",
	"S": "011100010001110", "T": "111010010010010", "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110",
	"4": "101101111001001", "5": "111100110001110", "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
	"-": "000000111000000", ".": "000000000000010", "/": "001001010100100", "_": "000000000000111", "(": "001010010010001", ")": "100010010010100", ",": "000000000010100", ":": "000010000010000",
}
## The district a kind of building is tried in (it changes the ground and the yard).
const DISTRICT_OF := {"house": "suburb", "apartments": "main", "shop": "main", "office": "main", "industrial": "industrial", "civic": "civic", "farm": "edge", "outbuilding": "suburb"}

var tids := {}
var kit
var gen
var img: Image


func _initialize() -> void:
	_main.call_deferred()


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--%s=" % name):
			return String(a).trim_prefix("--%s=" % name)
	return default


func _setup() -> void:
	var lay: Dictionary = TownKit.layouts()
	var base: Dictionary = GD.load_all()
	var tt: Dictionary = base.terrainTypes.duplicate(true)
	for k in lay.terrain:
		tt[k] = {"id": int(lay.terrain[k].id), "file": String(lay.terrain[k].file)}
	for k in tt:
		tids[k] = int(tt[k].id)
	kit = TownKit.new()
	kit.setup(lay, tids)
	gen = BuildingGen.new()
	gen.setup(lay.props, tids, kit, 192)


## The BUILDING CATALOGUE: one picture of every plan (the building and what is round it, cropped), the plans in groups by category with a heading, each with its name, its size and its roof.
func _catalogue(path: String, ts: int) -> void:
	var groups := {}
	var order: Array = ["house", "apartments", "shop", "office", "industrial", "civic", "farm", "outbuilding"]
	var titles := {"house": "HOUSES", "apartments": "APARTMENT BLOCKS", "shop": "SHOPS", "office": "OFFICES", "industrial": "INDUSTRIAL", "civic": "CIVIC", "farm": "FARM", "outbuilding": "OUTBUILDINGS"}
	for c in order:
		groups[c] = []
	var count := 0
	for pl in Recipes.all_plans():
		var id := String(pl.id)
		var cat := String(pl.cat)
		var sample := {}
		if String(pl.s) == "extra":
			sample = _extra_sample(id)
		elif id == "start":
			continue
		else:
			sample = _plan_sample(pl)
		if sample.is_empty():
			print("catalogue: no sample of ", id)
			continue
		sample["id"] = id
		sample["name"] = String(pl.name)
		(groups[cat] as Array).append(sample)
		count += 1
	# lay the groups out: a heading, then the plans of the group in rows
	var width := 2400
	var pad := 10
	var rows_y := 8
	var placed: Array = []
	var headings: Array = []
	for c in order:
		var list: Array = groups[c]
		if list.is_empty():
			continue
		headings.append([titles[c] + " (%d plans)" % list.size(), rows_y])
		rows_y += 26
		var x := pad
		var row_h := 0
		for s in list:
			var im: Image = _crop_image(s, ts)
			var w := maxi(im.get_width(), 132)
			if x + w + pad > width:
				x = pad
				rows_y += row_h + 34
				row_h = 0
			placed.append([s, im, x, rows_y + 22])
			x += w + pad
			row_h = maxi(row_h, im.get_height())
		rows_y += row_h + 40
	var out := Image.create(width, rows_y + 8, false, Image.FORMAT_RGBA8)
	out.fill(Color("20242a"))
	img = out
	for h in headings:
		_text(String(h[0]), 10, int(h[1]), 3, Color("ffd060"))
	for p in placed:
		var im2: Image = p[1]
		out.blit_rect(im2, Rect2i(0, 0, im2.get_width(), im2.get_height()), Vector2i(int(p[2]), int(p[3])))
		var s2: Dictionary = p[0]
		var fac: Dictionary = (s2.out.buildings[s2.bi] as Dictionary).get("facade", {})
		var nm := String(s2.name).substr(0, int((maxi(im2.get_width(), 132)) / 4))
		_text(nm, int(p[2]), int(p[3]) - 16, 1, Color("ffe38a"))
		var box: Vector2i = Rect2i(s2.out.buildings[s2.bi].box).size
		_text("%dx%d %s" % [box.x, box.y, String(fac.get("style", ""))], int(p[2]), int(p[3]) - 8, 1, Color("90a8c0"))
	out.save_png(path)
	print("catalogue: %d plans, %s (%d x %d)" % [count, path, out.get_width(), out.get_height()])


## A typical building of a plan: an intact one on a lot that fits it with room round it, no fence, no ruin, no shed.
func _plan_sample(pl: Dictionary) -> Dictionary:
	var rec: Dictionary = Recipes.recipe(String(pl.id))
	var kind := String(pl.k)
	for t in 120:
		var rng := RandomNumberGenerator.new()
		rng.seed = 424242 + t * 131 + String(pl.id).hash()
		var aw := rng.randi_range(24, 46)
		var depth := rng.randi_range(17, 30)
		var plan: Dictionary = Plans.plan_of(rec, kind, aw, depth, rng)
		if plan.is_empty():
			continue
		var box: Vector2i = plan.box
		var lot_w := mini(aw, box.x + maxi(int(plan.margin), 3))
		var dist := String(DISTRICT_OF.get(String(pl.cat), "suburb"))
		var spec := {"kind": kind, "district": dist, "rect": Rect2i(0, 0, lot_w, depth), "front": "N" if t % 2 == 0 else "S", "plan": plan, "seed": 7000 + t, "start": false, "clear": false, "mat": 1,
			"fenced": false, "yard": "lawn", "ruin": false, "barricade": false, "boarded": false, "burnt": false, "shed": false}
		var out: Dictionary = gen.build(spec)
		if not _check(out, plan, lot_w, depth).is_empty():
			continue
		return {"out": out, "spec": spec, "bi": 0}
	return {}


## A small building of the yard (a shed, a garage, a silo...): a lot with a house and one of these, cropped to it.
func _extra_sample(id: String) -> Dictionary:
	var edge := id in ["silo", "coop_small", "tractor_shed"]
	var host := "farmhouse" if edge else "ranch"
	var rec: Dictionary = Recipes.recipe("farmhouse" if edge else "ranch")
	for t in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99 + t * 71 + id.hash()
		var plan: Dictionary = Plans.plan_of(rec, host, 40, 28, rng)
		if plan.is_empty():
			continue
		var box: Vector2i = plan.box
		var spec := {"kind": host, "district": "edge" if edge else "suburb", "rect": Rect2i(0, 0, mini(40, box.x + 12), 28), "front": "N", "plan": plan, "seed": 500 + t, "start": false, "clear": false, "mat": 1,
			"fenced": false, "yard": "lawn", "ruin": false, "barricade": false, "boarded": false, "burnt": false, "shed": true}
		var out: Dictionary = gen.build(spec)
		if out.buildings.size() > 1 and String(out.buildings[1].get("var", "")) == id:
			return {"out": out, "spec": spec, "bi": 1}
	return {}


## The picture of a sample cropped to its building and what is round it.
func _crop_image(s: Dictionary, ts: int) -> Image:
	var full := _plan_image(s, ts)
	var b: Dictionary = s.out.buildings[s.bi]
	var lot_pos: Vector2i = Rect2i(s.spec.rect).position
	var r := Rect2i(b.box)
	r = Rect2i(r.position - lot_pos, r.size).grow(4)
	var lw: int = s.out.cv.W
	var lh: int = s.out.cv.H
	r = r.intersection(Rect2i(0, 0, lw, lh))
	return full.get_region(Rect2i(r.position * ts, r.size * ts))


func _main() -> void:
	_setup()
	if "--catalogue" in OS.get_cmdline_user_args():
		_catalogue(_arg("sheet", "/tmp/catalogue.png"), int(_arg("ts", "11")))
		quit()
		return
	var trials := int(_arg("trials", "40"))
	var seed_base := int(_arg("seed", "1"))
	var only := _arg("only", "")
	var only_ids: Array = only.split(",") if only != "" else []
	var quiet := "--quiet" in OS.get_cmdline_user_args()
	var sheet := _arg("sheet", "")
	var ts := int(_arg("ts", "10"))
	var plans: Array = Recipes.all_plans()
	var rows: Array = []
	var samples: Array = []
	var fail_samples: Array = []
	var want_fails := "--fails" in OS.get_cmdline_user_args()
	var bad_total := 0
	var t0 := Time.get_ticks_usec()
	var builds := 0
	for pl in plans:
		var id := String(pl.id)
		if not only_ids.is_empty() and not (id in only_ids):
			continue
		if String(pl.s) == "extra":
			continue
		var rec: Dictionary = Recipes.recipe(id)
		var kind := String(pl.k)
		if id == "start":
			continue
		var fits := 0
		var ok := 0
		var fails := {}
		var rooms_sum := 0
		var rooms_min := 99
		var cont_sum := 0
		var best_sample: Dictionary = {}
		for t in trials:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_base * 100003 + t * 7919 + id.hash()
			var aw := rng.randi_range(10, 46)
			var depth := rng.randi_range(10, 30)
			var plan: Dictionary = Plans.plan_of(rec, kind, aw, depth, rng)
			if plan.is_empty():
				continue
			fits += 1
			var box: Vector2i = plan.box
			var lot_w := mini(aw, box.x + int(plan.margin))
			if aw - lot_w < 5 and aw - lot_w >= 0:
				lot_w = aw
			var front := "N" if rng.randf() < 0.5 else "S"
			var dist := String(DISTRICT_OF.get(String(pl.cat), "suburb"))
			var spec := {"kind": kind, "district": dist, "rect": Rect2i(0, 0, lot_w, depth), "front": front, "plan": plan, "seed": 1000 + t, "start": false, "clear": false, "mat": 1,
				"fenced": rng.randf() < 0.3 and kind != "terrace", "yard": "lawn", "ruin": rng.randf() < 0.1 and Array(plan.parts).size() >= 2, "barricade": rng.randf() < 0.08, "boarded": rng.randf() < 0.1,
				"burnt": rng.randf() < 0.05, "shed": rng.randf() < 0.4 and dist == "suburb"}
			var out: Dictionary = gen.build(spec)
			builds += 1
			var problems := _check(out, plan, lot_w, depth)
			if problems.is_empty():
				ok += 1
			else:
				if want_fails and fail_samples.size() < 8:
					fail_samples.append({"id": id, "out": out, "spec": spec, "rooms": 0, "problems": problems})
				for p in problems:
					fails[p] = int(fails.get(p, 0)) + 1
			var nrooms := 0
			for a in out.cv.areas:
				if bool(a.indoor) and int(a.get("b", 0)) == 0:
					nrooms += 1
			rooms_sum += nrooms
			rooms_min = mini(rooms_min, nrooms)
			cont_sum += out.cv.cands.size()
			if problems.is_empty() and (best_sample.is_empty() or (not bool(spec.ruin) and not bool(spec.burnt) and rng.randf() < 0.3)):
				best_sample = {"id": id, "out": out, "spec": spec, "rooms": nrooms}
		var line := "%-22s fits %3d/%d ok %3d  rooms avg %.1f min %d  containers avg %.1f" % [id, fits, trials, ok, float(rooms_sum) / maxf(1.0, float(fits)), rooms_min if fits > 0 else 0, float(cont_sum) / maxf(1.0, float(fits))]
		if fits > ok:
			line += "  FAILS %s" % JSON.stringify(fails)
			bad_total += fits - ok
		if fits == 0:
			line += "  NEVER FITS"
			bad_total += 1
		if not quiet or fits != ok or fits == 0:
			print(line)
		if not best_sample.is_empty():
			samples.append(best_sample)
	print("plans %d, builds %d, bad %d, %.1f ms a build" % [rows.size() + samples.size(), builds, bad_total, float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, float(builds))])
	if want_fails and not fail_samples.is_empty():
		for fs in fail_samples:
			print("FAIL SAMPLE %s %s lot %s front %s plan %s" % [String(fs.id), JSON.stringify(fs.problems), str(fs.spec.rect), String(fs.spec.front), str(fs.spec.plan.get("parts"))])
		_sheet(fail_samples, ts).save_png(sheet if sheet != "" else "/tmp/plan_lab_fails.png")
	elif sheet != "":
		_sheet(samples, ts).save_png(sheet)
		print("sheet: %s" % sheet)
	quit(1 if bad_total > 0 else 0)


## What must hold of a built lot: [] when it does.
func _check(out: Dictionary, plan: Dictionary, lw: int, lh: int) -> Array:
	var problems: Array = []
	var cv = out.cv
	var reach: PackedByteArray = out.reach
	for b in out.buildings:
		for pr in b.parts:
			var r := Rect2i(pr)
			if r.position.x < 0 or r.position.y < 0 or r.end.x > lw or r.end.y > lh:
				problems.append("outside the lot")
				break
	var by_house := {}
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var bi := int(a.get("b", 0))
		if not by_house.has(bi):
			by_house[bi] = 0
		by_house[bi] += 1
		var rr: Rect2i = a.rect
		var seen := false
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				if reach[y * cv.W + x] != 0:
					seen = true
		if not seen:
			problems.append("room not reached: " + String(a.name))
		if rr.size.x < 2 or rr.size.y < 2:
			problems.append("tiny room: " + String(a.name))
	if by_house.is_empty():
		problems.append("no rooms")
	var door_t := int(tids.DOOR_WOOD)
	var doors := 0
	for i in cv.terrain.size():
		if cv.terrain[i] == door_t:
			doors += 1
	if doors == 0:
		problems.append("no doors")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	if int(plan.get("units", 0)) > 0:
		var fronts := 0
		for b in out.buildings:
			fronts += (b.front_door as Array).size()
		if fronts < 2:
			problems.append("units without doors")
	return problems


# ----------------------------------------------------------------------------- the sheet --

func _floor_color(tn: String) -> Color:
	match tn:
		"WOOD":
			return Color("b08050")
		"KITCHEN":
			return Color("96be96")
		"LINO":
			return Color("aab9c8")
		"CONCRETE":
			return Color("7d7d82")
		"TERRAZZO":
			return Color("cdc8be")
		"DIRT":
			return Color("826441")
		"SOIL":
			return Color("503c28")
		"GRASS":
			return Color("5a7d46")
		"SIDEWALK":
			return Color("a5a5a0")
		"ASPHALT":
			return Color("3c3c42")
		"YARD":
			return Color("8a7a5a")
	return Color("707070")


func _obj_color(k: String) -> Color:
	if k.begins_with("bed") or k.begins_with("cot") or k == "mattress" or k == "bedroll":
		return Color("6e8cc8")
	if k in ["fridge", "stove", "kitchen_counter", "kitchen_sink", "washer", "dryer"]:
		return Color("e1e1d7")
	if k.begins_with("shelf") or k == "bookshelf":
		return Color("d69646")
	if k in ["cupboard", "wardrobe", "dresser", "nightstand"]:
		return Color("96643c")
	if k in ["crate", "box", "toolbox"]:
		return Color("bea064")
	if k.begins_with("desk") or k in ["workbench", "dining_table", "coffee_table", "table"]:
		return Color("8c9646")
	if k == "bench" or k == "chair" or k == "armchair" or k == "sofa" or k == "loveseat":
		return Color("aa785a")
	if k.begins_with("rug"):
		return Color(0.6, 0.3, 0.5, 0.5)
	if k.begins_with("car"):
		return Color("c8c8c8")
	if k == "bush":
		return Color("3c6e3c")
	if k in ["shop_shelf", "checkout", "display_case", "cooler", "tool_chest", "vanity", "toy_chest", "mannequin", "cart"]:
		return Color("e0a050")
	if k in ["piano", "fireplace", "aquarium", "crib", "bunk_bed", "shower", "washer", "dining_table_sq", "barber_chair", "cafe_table", "bar_stool", "plant_floor", "rocking_chair", "tire_stack", "jerrycan"]:
		return Color("9ab0d0")
	if k in ["gas_pump", "laundry", "trampoline", "bbq", "gnome", "toys", "sandpit", "paddling_pool", "flower_bed", "veg_patch", "weeds", "woodpile", "rain_barrel", "barrow", "birdbath", "deck_chair", "picnic_table", "kennel", "doormat", "plant_pot", "compost_heap", "note"]:
		return Color("70b070")
	return Color("c864c8")


func _text(s: String, x: int, y: int, ts: int, c: Color) -> void:
	var at := 0
	for ch in s.to_upper():
		if GLYPHS.has(ch):
			var g: String = GLYPHS[ch]
			for r in 5:
				for k in 3:
					if g[r * 3 + k] == "1":
						img.fill_rect(Rect2i(x + (at + k) * ts, y + r * ts, ts, ts), c)
		at += 4


## One building's picture: the lot's ground, the walls and the doors, the furniture, then the roof as a colour over the parts.
func _plan_image(sample: Dictionary, ts: int) -> Image:
	var out: Dictionary = sample.out
	var cv = out.cv
	var lw: int = cv.W
	var lh: int = cv.H
	var im := Image.create(lw * ts, lh * ts, false, Image.FORMAT_RGBA8)
	var ids := {}
	for k in tids:
		ids[int(tids[k])] = String(k)
	for y in lh:
		for x in lw:
			var i: int = y * lw + x
			var tn: String = ids.get(int(cv.terrain[i]), "")
			var c := _floor_color(tn)
			if tn == "DOOR_WOOD":
				c = Color.WHITE
			elif tn == "WALL_BRICK":
				c = Color("5a3c34")
			elif tn == "WALL_PLASTER":
				c = Color("8c6a5a")
			elif tn == "WALL_METAL":
				c = Color("c8ccd2")
			im.fill_rect(Rect2i(x * ts, y * ts, ts, ts), c)
	for o in cv.objects:
		if int(o.layer) == 1:
			continue
		var px := int((float(o.cx) - float(o.w) / 2.0) * ts)
		var py := int((float(o.cy) - float(o.h) / 2.0) * ts)
		im.fill_rect(Rect2i(px + 1, py + 1, int(float(o.w) * ts) - 2, int(float(o.h) * ts) - 2), _obj_color(String(o.kind)))
	for t in cv.trees:
		var cxp := int(float(t.x) * ts)
		var cyp := int(float(t.y) * ts)
		for dy in range(-ts / 2, ts / 2 + 1):
			for dx in range(-ts / 2, ts / 2 + 1):
				if dx * dx + dy * dy <= ts * ts / 4 and cxp + dx >= 0 and cyp + dy >= 0 and cxp + dx < im.get_width() and cyp + dy < im.get_height():
					im.set_pixel(cxp + dx, cyp + dy, Color("1f5a24"))
	var lot_pos: Vector2i = Rect2i(sample.spec.rect).position
	# the facade: the roof's colour over the parts (a hint: a half see-through wash), a canopy, a porch, an awning
	for b in out.buildings:
		var fac: Dictionary = b.get("facade", {})
		if fac.is_empty():
			continue
		var tint: Color = fac.get("tint", Color(0.7, 0.4, 0.3))
		for pr in b.parts:
			var r := Rect2i(pr)
			var rr := Rect2i((r.position - lot_pos) * ts, r.size * ts)
			for y in range(rr.position.y, rr.end.y):
				for x in range(rr.position.x, rr.end.x):
					if (x + y) % 2 == 0 and x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
						var c0: Color = im.get_pixel(x, y)
						im.set_pixel(x, y, c0.lerp(tint, 0.55))
		for cnp in fac.get("canopies", []):
			var cr: Rect2 = cnp.r
			var col := Color(0.9, 0.85, 0.5, 0.5)
			var ck := String(cnp.kind)
			if ck.begins_with("awn"):
				col = Color(0.9, 0.3, 0.3, 0.55)
			elif ck == "gas":
				col = Color(0.9, 0.9, 0.9, 0.45)
			var rect := Rect2i(int((cr.position.x - lot_pos.x) * ts), int((cr.position.y - lot_pos.y) * ts), int(cr.size.x * ts), int(cr.size.y * ts))
			for y in range(maxi(0, rect.position.y), mini(im.get_height(), rect.end.y)):
				for x in range(maxi(0, rect.position.x), mini(im.get_width(), rect.end.x)):
					if (x / 2 + y / 2) % 2 == 0:
						im.set_pixel(x, y, im.get_pixel(x, y).lerp(col, 0.6))
	return im


func _sheet(samples: Array, ts: int) -> Image:
	var tiles: Array = []
	for s in samples:
		tiles.append([s, _plan_image(s, ts)])
	var width := 2200
	var x := 6
	var y := 6
	var row_h := 0
	var placements: Array = []
	for t in tiles:
		var pim: Image = t[1]
		if x + pim.get_width() + 6 > width:
			x = 6
			y += row_h + 22
			row_h = 0
		placements.append([x, y])
		x += pim.get_width() + 8
		row_h = maxi(row_h, pim.get_height())
	var out := Image.create(width, y + row_h + 24, false, Image.FORMAT_RGBA8)
	out.fill(Color("20242a"))
	img = out
	for i in tiles.size():
		var pim2: Image = tiles[i][1]
		out.blit_rect(pim2, Rect2i(0, 0, pim2.get_width(), pim2.get_height()), Vector2i(placements[i][0], placements[i][1] + 8))
		var s: Dictionary = tiles[i][0]
		var fac: Dictionary = (s.out.buildings[0] as Dictionary).get("facade", {})
		var label := "%s %dx%d %s" % [String(s.id), Vector2i(s.spec.plan.box).x, Vector2i(s.spec.plan.box).y, String(fac.get("style", ""))]
		_text(label, placements[i][0], placements[i][1] + 1, 1, Color("ffe38a"))
	return out
