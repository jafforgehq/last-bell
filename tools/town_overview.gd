## The whole town as one colour-coded PNG (One House, TOWNGEN), to LOOK at the layout: the districts tinted, the streets (the main avenue and every street named), the buildings by
## type (residential brown, commercial blue, industrial violet, civic red, farm yellow; the floor lighter than the walls, doors white), the start house (a green frame), the rescue
## spots (cyan, numbered near to far; of the other candidates a small dot in the colour of their frame), the landmarks (a yellow diamond), the trees and the cars. ARRIVAL: the entry (a
## magenta dot and an arrow into the town, the painted chevrons small yellow marks) and every candidate (a frame of its lot: green best, yellow ok, orange poor, under it the tier, rooms, yard and the
## distance from the entry). No window needed:
##
##   godot --headless --path <project> --script tools/town_overview.gd -- --seed=1 --out=/tmp/town1.png [--scale=6] [--blocks=6] [--stats]
##
## `--stats` prints the numbers too (houses, rooms, parts, kinds, district areas, the time to make the town).
extends SceneTree

const TownGen := preload("res://scripts/town/town_gen.gd")
const Districts := preload("res://scripts/town/town_districts.gd")

const GLYPHS := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110", "E": "111100110100111", "F": "111100110100100",
	"G": "011100101101011", "H": "101101111101101", "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100", "Q": "010101101110011", "R": "110101110101101",
	"S": "011100010001110", "T": "111010010010010", "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110",
	"4": "101101111001001", "5": "111100110001110", "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
	"-": "000000111000000", ".": "000000000000010", "/": "001001010100100",
}
const TYPE_COLORS := {
	"residential": Color("b5784a"), "commercial": Color("4f86c6"), "industrial": Color("8a6fb0"), "civic": Color("c8453f"), "farm": Color("d1b83a"),
}

var img: Image
var S := 6
var W := 192


func _init() -> void:
	var seed_value := 1
	var out := "/tmp/town_overview.png"
	var blocks := 6
	var stats := false
	for a in OS.get_cmdline_user_args():
		var t := String(a)
		if t.begins_with("--seed="):
			seed_value = int(t.trim_prefix("--seed="))
		elif t.begins_with("--out="):
			out = t.trim_prefix("--out=")
		elif t.begins_with("--scale="):
			S = int(t.trim_prefix("--scale="))
		elif t.begins_with("--blocks="):
			blocks = int(t.trim_prefix("--blocks="))
		elif t == "--stats":
			stats = true
	var t0 := Time.get_ticks_usec()
	var town: Dictionary = TownGen.make(seed_value, {"blocks": blocks})
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var plan_rect := ""
	var gallery := false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--plan="):
			plan_rect = String(a).trim_prefix("--plan=")
		elif String(a) == "--gallery":
			gallery = true
	if plan_rect != "":
		# a floor plan of a rectangle of tiles (no roofs): the rooms, the walls, the doors, the furniture
		var v := plan_rect.split(",")
		var ts := S if S >= 8 else 16
		var im := _plan_image(town, Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3])), ts)
		im.save_png(out)
		print("plan of %s: %s" % [plan_rect, out])
	elif gallery:
		var kinds: Array = []
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--kinds="):
				kinds = String(a).trim_prefix("--kinds=").split(",")
		var im := _gallery(town, S if S >= 8 else 12, kinds)
		im.save_png(out)
		print("gallery: %s (%d x %d)" % [out, im.get_width(), im.get_height()])
	else:
		_draw(town)
		img.save_png(out)
		print("overview of seed %d: %s (%d x %d), generated in %.0f ms" % [seed_value, out, img.get_width(), img.get_height(), ms])
	if stats:
		_print_stats(town, ms)
	quit()


# ------------------------------------------------------------------- floor plans --

func _obj_color(k: String) -> Color:
	if k.begins_with("bed") or k.begins_with("cot"):
		return Color("6e8cc8")
	if k in ["fridge", "stove", "counter", "counter2", "counter3"]:
		return Color("e1e1d7")
	if k.begins_with("shelf"):
		return Color("d69646")
	if k in ["cabinet", "locker"]:
		return Color("96643c")
	if k in ["crate", "crate_ammo", "cans", "waterpack", "barrel", "scrap", "tires"]:
		return Color("bea064")
	if k.begins_with("desk") or k in ["teacherdesk", "longtable", "picnic", "workbench", "worktable", "radiodesk"]:
		return Color("8c9646")
	if k == "bench":
		return Color("aa785a")
	if k.begins_with("rug"):
		return Color(0.6, 0.3, 0.5, 0.5)
	if k == "lamp":
		return Color("ffe664")
	if k.begins_with("car") or k.begins_with("van") or k.begins_with("bus") or k.begins_with("pickup"):
		return Color("c8c8c8")
	if k.begins_with("cont_"):
		return Color("b4552d")
	if k == "shrub":
		return Color("3c6e3c")
	return Color("c864c8")


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
		"WATER":
			return Color("3c6eaa")
	return Color("707070")


func _plan_image(town: Dictionary, rect: Rect2i, ts: int) -> Image:
	var im := Image.create(rect.size.x * ts, rect.size.y * ts, false, Image.FORMAT_RGBA8)
	var save_img := img
	var save_s := S
	img = im
	S = ts
	var d: Dictionary = town.data
	var ids := {}
	for k in d.terrainTypes:
		ids[int(d.terrainTypes[k].id)] = String(k)
	var W2 := int(town.size.x)
	var th: PackedInt32Array = town.tile_house
	for y in rect.size.y:
		for x in rect.size.x:
			var gx := rect.position.x + x
			var gy := rect.position.y + y
			if gx < 0 or gy < 0 or gx >= W2 or gy >= W2:
				continue
			var i := gy * W2 + gx
			var tn: String = ids.get(int(d.terrain[i]), "")
			var c := _floor_color(tn)
			if tn == "DOOR_WOOD":
				c = Color.WHITE
			elif tn.begins_with("WALL"):
				c = Color("3a2c28") if int(th[i]) >= 0 else Color("8a9098")
			_rect(x * ts, y * ts, ts, ts, c)
			if tn.begins_with("WALL") and int(th[i]) >= 0:
				var wm := tn
				if wm == "WALL_PLASTER":
					_rect(x * ts + 1, y * ts + 1, ts - 2, ts - 2, Color("5a4a44"))
	for r in town.rooms:
		var rr: Rect2i = r.rect
		if rr.intersects(rect):
			_text(String(r.name).substr(0, 10), (rr.position.x - rect.position.x) * ts + 2, (rr.position.y - rect.position.y) * ts + 2, maxi(1, ts / 12), Color(1, 1, 1, 0.95))
	for o in d.objects:
		if int(o.layer) == 1:
			continue
		var cx := float(o.cx)
		var cy := float(o.cy)
		if not rect.has_point(Vector2i(int(cx), int(cy))):
			continue
		var w := float(o.w)
		var h := float(o.h)
		if String(o.kind) in ["lamppost", "hydrant", "awning_r", "awning_b", "awning_g", "toolboard", "chalkboard"]:
			continue
		var px := int((cx - w / 2.0 - float(rect.position.x)) * ts)
		var py := int((cy - h / 2.0 - float(rect.position.y)) * ts)
		var col := _obj_color(String(o.kind))
		_rect(px + 1, py + 1, int(w * ts) - 2, int(h * ts) - 2, col)
		if ts >= 14:
			_text(String(o.kind).substr(0, 3), px + 2, py + 2, maxi(1, ts / 20), Color(0, 0, 0, 0.8), false, false)
	for t in d.trees:
		var tx := float(t.x)
		var ty := float(t.y)
		if rect.has_point(Vector2i(int(tx), int(ty))):
			var cxp := int((tx - float(rect.position.x)) * ts)
			var cyp := int((ty - float(rect.position.y)) * ts)
			for dy in range(-ts / 2, ts / 2 + 1):
				for dx in range(-ts / 2, ts / 2 + 1):
					if dx * dx + dy * dy <= ts * ts / 4:
						_px(cxp + dx, cyp + dy, Color("1f5a24"))
	for h in town.houses:
		for p in h.parts:
			var pr: Rect2i = p
			if pr.intersects(rect):
				_frame(Rect2i(pr.position - rect.position, pr.size), Color(1, 0.2, 0.2, 0.7), 1)
	img = save_img
	S = save_s
	return im


## One floor plan of a house of each kind (and the two or three parted ones), side by side: a catalogue of what the generator builds.
func _gallery(town: Dictionary, ts: int, kinds: Array = []) -> Image:
	var firsts := {}
	var picks: Array = []
	for h in town.houses:
		var key := String(h.kind)
		if not kinds.is_empty() and not (key in kinds):
			continue
		var n := int(firsts.get(key, 0))
		var want := 2 if (h.parts.size() > 1 or key in ["church", "apartments", "school"]) else 1
		if n < want:
			firsts[key] = n + 1
			picks.append(h)
	var plans: Array = []
	for h in picks:
		var lot: Rect2i = h.lot
		var r: Rect2i = lot.grow(0)
		plans.append([h, _plan_image(town, r, ts)])
	var width := 1900
	var x := 0
	var y := 0
	var row_h := 0
	var placements: Array = []
	for p in plans:
		var pim: Image = p[1]
		if x + pim.get_width() > width:
			x = 0
			y += row_h + 14
			row_h = 0
		placements.append([x, y])
		x += pim.get_width() + 10
		row_h = maxi(row_h, pim.get_height())
	var out := Image.create(width, y + row_h + 14, false, Image.FORMAT_RGBA8)
	out.fill(Color("20242a"))
	for i in plans.size():
		var pim: Image = plans[i][1]
		out.blit_rect(pim, Rect2i(0, 0, pim.get_width(), pim.get_height()), Vector2i(placements[i][0], placements[i][1] + 8))
		var save_img := img
		img = out
		_text(String(plans[i][0].kind).to_upper(), placements[i][0], placements[i][1], 1, Color("ffe38a"), false, false)
		img = save_img
	return out


func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


func _tile_rect(r: Rect2i, c: Color) -> void:
	_rect(r.position.x * S, r.position.y * S, r.size.x * S, r.size.y * S, c)


func _frame(r: Rect2i, c: Color, t: int) -> void:
	var x := r.position.x * S
	var y := r.position.y * S
	var w := r.size.x * S
	var h := r.size.y * S
	_rect(x, y, w, t, c)
	_rect(x, y + h - t, w, t, c)
	_rect(x, y, t, h, c)
	_rect(x + w - t, y, t, h, c)


## Text in the 3 x 5 pixel font at pixel (x, y), each dot `ts` pixels, `vertical` turns it a quarter.
func _text(s: String, x: int, y: int, ts: int, c: Color, vertical: bool = false, shadow: bool = true) -> void:
	var at := 0
	for ch in s.to_upper():
		if GLYPHS.has(ch):
			var g: String = GLYPHS[ch]
			for r in 5:
				for k in 3:
					if g[r * 3 + k] == "1":
						var px := x + (at + k) * ts if not vertical else x + r * ts
						var py := y + r * ts if not vertical else y + (at + k) * ts
						if shadow:
							_rect(px + 1, py + 1, ts, ts, Color(0, 0, 0, 0.8))
						_rect(px, py, ts, ts, c)
		at += 4


func _draw(town: Dictionary) -> void:
	W = int(town.size.x)
	img = Image.create(W * S, W * S, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var d: Dictionary = town.data
	var ids := {}
	for k in d.terrainTypes:
		ids[int(d.terrainTypes[k].id)] = String(k)
	var terrain: Array = d.terrain
	var solid: Array = d.solidZ
	var dmap: PackedByteArray = town.districts.map
	var names: Array = town.districts.names
	var th: PackedInt32Array = town.tile_house
	var houses: Array = town.houses
	for y in W:
		for x in W:
			var i := y * W + x
			var tn: String = ids.get(int(terrain[i]), "")
			var c := Color(0.3, 0.3, 0.3)
			var dv := int(dmap[i])
			var tint: Color = Districts.GROUND_TINT.get(String(names[dv - 1]) if dv > 0 else "edge", Color(0.4, 0.5, 0.3))
			var hid := int(th[i])
			if hid >= 0:
				var tc: Color = TYPE_COLORS.get(String(houses[hid].type), Color.GRAY)
				if tn == "DOOR_WOOD":
					c = Color.WHITE
				elif tn.begins_with("WALL") and int(solid[i]) != 0:
					c = tc.darkened(0.35)
				else:
					c = tc.lightened(0.25)
			else:
				match tn:
					"ASPHALT":
						c = Color("3d3d42")
					"SIDEWALK":
						c = Color("a9a9a2")
					"CONCRETE":
						c = Color("7d7d82")
					"DIRT":
						c = Color("8c6e45")
					"SOIL":
						c = Color("5a4630")
					"WATER", "ROOF":
						c = Color("3c6eb4")
					"GRASS":
						c = tint
					"DOOR_WOOD":
						c = Color.WHITE
					_:
						if tn.begins_with("WALL") and int(solid[i]) != 0:
							c = Color("c9c4b8")
						else:
							c = tint.lightened(0.1)
			_rect(x * S, y * S, S, S, c)
	# the lots of the yards: a faint frame
	for lot in town.lots:
		if int(lot.house) < 0 and String(lot.kind) in ["park", "plaza", "field", "woods", "meadow"]:
			_frame(lot.rect, Color(1, 1, 1, 0.12), 1)
	# trees and cars
	for t in d.trees:
		var cx := int(float(t.x) * S)
		var cy := int(float(t.y) * S)
		_rect(cx - 1, cy - 1, maxi(2, S / 2), maxi(2, S / 2), Color("1f4d22"))
	for o in d.objects:
		var k := String(o.kind)
		if k.begins_with("car_") or k.begins_with("van_") or k.begins_with("bus_") or k.begins_with("pickup"):
			_rect(int((float(o.cx) - float(o.w) / 2.0) * S), int((float(o.cy) - float(o.h) / 2.0) * S), int(float(o.w) * S), int(float(o.h) * S), Color("d8d8d8"))
		elif k.begins_with("cont_"):
			_rect(int((float(o.cx) - float(o.w) / 2.0) * S), int((float(o.cy) - float(o.h) / 2.0) * S), int(float(o.w) * S), int(float(o.h) * S), Color("b4552d"))
	# district names at the middle of the blocks
	for b in town.districts.blocks:
		var r: Rect2i = b.rect
		var nm := String(b.district).to_upper()
		var tw := nm.length() * 4 * 2
		_text(nm, r.position.x * S + (r.size.x * S - tw) / 2, r.position.y * S + (r.size.y * S) / 2 - 5, 2, Color(1, 1, 1, 0.9))
	# street names
	for rd in town.streets.roads:
		if String(rd.kind) == "alley":
			continue
		var r: Rect2i = rd.rect
		var nm := String(rd.name).to_upper()
		if String(rd.dir) == "h":
			var span := r.size.x * S
			var tw := nm.length() * 4 * 2
			if tw < span:
				_text(nm, r.position.x * S + (span - tw) / 2, r.position.y * S + (r.size.y * S - 10) / 2, 2, Color("ffe38a"))
		else:
			var span := r.size.y * S
			var tw := nm.length() * 4 * 2
			if tw < span:
				_text(nm, r.position.x * S + (r.size.x * S - 10) / 2, r.position.y * S + (span - tw) / 2, 2, Color("ffe38a"), true)
	# landmarks
	for lm in town.landmarks:
		var p: Vector2 = lm.pos
		var cx := int(p.x * S)
		var cy := int(p.y * S)
		var rad := S * 2
		for dy in range(-rad, rad + 1):
			var half := rad - absi(dy)
			_rect(cx - half, cy + dy, half * 2 + 1, 1, Color("ffd400"))
		_text(String(lm.kind).to_upper().substr(0, 6), cx + rad + 2, cy - 4, 2, Color("ffd400"))
	# the start house (the best candidate) and the rescue spots
	var sh: Dictionary = houses[int(town.start.house)]
	_frame(Rect2i(sh.lot), Color("39ff14"), 2)
	_text("START", sh.lot.position.x * S, maxi(0, sh.lot.position.y * S - 12), 2, Color("39ff14"))
	# ARRIVAL: the rescue spots of the other candidates (small dots in the colour of their candidate), the candidates (a frame of their lot, tier, rooms and the distance from the entry), the entry
	var tier_colors := {"best": Color("39ff14"), "ok": Color("ffe000"), "poor": Color("ff8a1f")}
	if town.has("rescue_for"):
		for c in town.get("candidates", []):
			if int(c.house) == int(town.start.house):
				continue
			var col: Color = tier_colors.get(String(c.tier), Color.WHITE)
			for r in town.rescue_for.get(str(int(c.house)), []):
				var p: Vector2 = r.pos
				var cx := int(p.x * S)
				var cy := int(p.y * S)
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if dx * dx + dy * dy <= 9:
							_px(cx + dx, cy + dy, col)
	var n := 1
	for r in town.rescue:
		var p: Vector2 = r.pos
		var cx := int(p.x * S)
		var cy := int(p.y * S)
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				if dx * dx + dy * dy <= 20:
					_px(cx + dx, cy + dy, Color("00e5ff"))
		_text(str(n), cx + 7, cy - 5, 2, Color("00e5ff"))
		n += 1
	for c in town.get("candidates", []):
		var ch: Dictionary = houses[int(c.house)]
		var col2: Color = tier_colors.get(String(c.tier), Color.WHITE)
		_frame(Rect2i(ch.lot), col2, 2)
		var lot_r: Rect2i = ch.lot
		_text("%s %dR %s %d" % [String(c.tier), int(c.rooms), String(c.yard), roundi(float(c.dist))], lot_r.position.x * S, lot_r.end.y * S + 3, 2, col2)
	if town.has("entry"):
		var e: Dictionary = town.entry
		var ep: Vector2 = e.pos
		var ex := int(ep.x * S)
		var ey := int(ep.y * S)
		var dirv := Vector2(1, 0) if String(e.face) == "E" else (Vector2(-1, 0) if String(e.face) == "W" else (Vector2(0, 1) if String(e.face) == "S" else Vector2(0, -1)))
		var magenta := Color("ff2bd6")
		for dy in range(-7, 8):
			for dx in range(-7, 8):
				if dx * dx + dy * dy <= 40:
					_px(ex + dx, ey + dy, magenta)
		for k in range(8, 34):
			var half := maxi(0, 6 - (k - 8) / 3)
			for w in range(-half, half + 1):
				_px(ex + int(dirv.x) * k + int(dirv.y) * w, ey + int(dirv.y) * k + int(dirv.x) * w, magenta)
		for ap in e.get("arrows", []):
			_rect(int(float(Vector2(ap).x) * S) - 3, int(float(Vector2(ap).y) * S) - 3, 6, 6, Color("ffe38a"))
		_text("ENTRY", clampi(ex - 20 if String(e.face) == "W" else ex + 10, 0, img.get_width() - 40), maxi(0, ey - 22), 2, magenta)
	_legend()


func _legend() -> void:
	var x := 6
	var y := 6
	var items := [["RESIDENTIAL", TYPE_COLORS.residential], ["COMMERCIAL", TYPE_COLORS.commercial], ["INDUSTRIAL", TYPE_COLORS.industrial], ["CIVIC", TYPE_COLORS.civic], ["FARM", TYPE_COLORS.farm], ["START/BEST", Color("39ff14")], ["OK", Color("ffe000")], ["POOR", Color("ff8a1f")], ["ENTRY", Color("ff2bd6")], ["RESCUE", Color("00e5ff")], ["LANDMARK", Color("ffd400")]]
	_rect(x - 3, y - 3, 120, items.size() * 14 + 4, Color(0, 0, 0, 0.7))
	for it in items:
		_rect(x, y, 10, 10, it[1])
		_text(String(it[0]), x + 14, y + 1, 2, Color.WHITE, false, false)
		y += 14


func _print_stats(town: Dictionary, ms: float) -> void:
	var st: Dictionary = town.stats
	print("houses %d (parts %d), rooms %d (per house %s), containers %d, dead %d, objects %d, trees %d, %.0f ms" % [st.houses, st.parts, st.rooms, str(st.rooms_per_house), st.containers, st.dead, st.objects, st.trees, ms])
	print("by kind: %s" % str(st.by_kind))
	print("by type: %s" % str(st.by_type))
	print("by district: %s" % str(st.by_district))
	print("district area (tiles, streets included): %s" % str(town.districts.area))
	var shapes := {}
	for h in town.houses:
		var key := "%dx%d/%d" % [Rect2i(h.rect).size.x, Rect2i(h.rect).size.y, h.parts.size()]
		shapes[key] = true
	print("distinct footprints (box size / parts): %d" % shapes.size())
	var lot_kinds := {}
	for lot in town.lots:
		lot_kinds[lot.kind] = int(lot_kinds.get(lot.kind, 0)) + 1
	print("lots %d by kind: %s" % [town.lots.size(), str(lot_kinds)])
	print("blocks %d, roads %d, landmarks %s" % [town.districts.blocks.size(), town.streets.roads.size(), str(town.landmarks.size())])
