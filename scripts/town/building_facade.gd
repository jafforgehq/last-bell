## The FACADE of a building (WORLD3): what is seen of it from the street and from above, decided by the building's recipe (scripts/town/building_recipes.gd `f`) and the dice. `make(ctx)` is called by
## `BuildingGen` for every building; the roof is painted from the result (scripts/render/roof_paint.gd), the house keeps it as `house.facade`.
##
## A FACADE: {"style": the roof of the main part ("gable", "hip", "flat", "lean", "saw", "dome", "glass"), "styles": [one for each part], "dirs": [the way a lean-to roof falls, for each part], "levels": [1 for
## a part that stands lower, else 0], "tint_id": 0 to 4 (scripts/render/roof_look.gd), "flat": the fill of a flat roof, "decor": [{"id", "x", "y"}] (what stands on the roof: tile coordinates of its middle),
## "canopies": [{"r": Rect2 (tiles), "kind": "awn_red" | "porch" | "gas" | "carport" | "dock" | "walk" | "portico" | "stoop", "dir": the way out from the wall}], "sign": {"icon", "x", "y"}, "holes": [cells],
## "tarps": [cells], "tarp_name", "state": "intact" | "ruined" | "burnt", "chimneys": [Vector2], "features": [names, for the census]}.
## `make` also says what the facade needs of the ground: "keep" (rects of tiles, in the town's, that no prop may stand on), "ground" ([rect, ground item name]: the wood of a porch, the asphalt of a
## forecourt) and "props" ([{"kind", "at"}]: a pump under a canopy, a car under a carport).
extends RefCounted

const RoofLook := preload("res://scripts/render/roof_look.gd")

const AWNINGS := ["red", "green", "blue", "yellow"]
const SIGNS := ["cart", "bread", "cup", "mug", "wrench", "book", "hanger", "plug", "drop", "scissors", "cross", "news"]
const TARPS := ["tarp_blue", "tarp_green", "tarp_orange"]


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var at := rng.randf() * total
	var last := ""
	for k in weights:
		last = String(k)
		at -= float(weights[k])
		if at < 0.0:
			return last
	return last


## `ctx`: {"kind", "var", "feat", "district", "state", "parts" (Rect2i in the town), "front" ("N"/"S"), "lot" (Rect2i), "doors" (the tiles of every outside door), "front_door" (its tiles), "fy", "seed",
## "clear" (a lot kept clear: no front features), "garage" (the index of the part that is a garage, or -1)}.
static func make(ctx: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ctx.seed) * 6151 + 17
	var feat: Dictionary = ctx.get("feat", {})
	var parts: Array = ctx.parts
	var kind := String(ctx.kind)
	var district := String(ctx.get("district", "suburb"))
	var state := String(ctx.get("state", "intact"))
	var front := String(ctx.front)
	var lot: Rect2i = ctx.lot
	var clear := bool(ctx.get("clear", false))
	var features: Array = []
	var fac := {"style": "gable", "styles": [], "dirs": [], "levels": [], "tint_id": 0, "flat": "flat_tar", "decor": [], "canopies": [], "holes": [], "tarps": [], "state": state, "chimneys": [], "features": features}
	var out := {"facade": fac, "keep": [], "ground": [], "props": []}
	if parts.is_empty():
		return out
	var burnt := state == "burnt"
	# ----- the roofs
	var style := _pick(feat.get("roof", {"gable": 1}), rng)
	var styles: Array = []
	var dirs: Array = []
	var levels: Array = []
	var main: Rect2i = parts[0]
	var out_dir := "n" if front == "N" else "s"
	for pi in parts.size():
		var st := style
		var pq: Rect2i = parts[pi]
		var dir := out_dir
		if pi > 0 and not (style in ["saw", "dome", "glass"]):
			var roll := rng.randf()
			match style:
				"gable":
					st = "gable" if roll < 0.55 else ("lean" if roll < 0.85 else "flat")
				"hip":
					st = "hip" if roll < 0.6 else "lean"
				_:
					st = style
			if pi == int(ctx.get("garage", -1)):
				st = "lean" if roll < 0.45 else ("flat" if roll < 0.7 else "gable")
		# a lean-to falls away from the main part: to the side it stands on, else to the street or away from it
		if pq.position.x < main.position.x:
			dir = "w"
		elif pq.end.x > main.end.x:
			dir = "e"
		elif pi > 0 and pq.position.y > main.position.y:
			dir = "s" if front == "N" else "n"
		elif rng.randf() < 0.4:
			dir = "n" if front == "N" else "s"
		else:
			dir = "s" if front == "N" else "n"
		styles.append(st)
		dirs.append(dir)
		levels.append(1 if (bool(feat.get("levels", 0)) and pi > 0) else 0)
	fac.style = style
	fac.styles = styles
	fac.dirs = dirs
	fac.levels = levels
	features.append("roof:" + style)
	if bool(feat.get("levels", 0)) and parts.size() > 1:
		features.append("split-level")
	# the colour
	var tw := {}
	for i in RoofLook.WEIGHTS.size():
		tw[str(i)] = RoofLook.WEIGHTS[i]
	fac.tint_id = int(_pick(tw, rng))
	var flats: Array = RoofLook.FLATS.get(district, RoofLook.FLATS.suburb)
	var fw := {}
	for f in flats:
		fw[String(f[0])] = float(f[1])
	fac.flat = _pick(fw, rng)
	if burnt:
		features.append("burnt")
	# ----- the cells the things on a roof keep clear of: the doors' and the canopies'
	var taken := {}
	for dt in ctx.get("doors", []):
		var t: Vector2i = dt
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				taken[Vector2i(t.x + dx, t.y + dy)] = true
	# ----- the front: porch, awning, canopy, sign
	var fd: Array = ctx.get("front_door", [])
	var wall_y := main.position.y if front == "N" else main.end.y - 1
	var door_c := Vector2(float(main.get_center().x), float(wall_y))
	var door_part: Rect2i = main
	if not fd.is_empty():
		var a: Vector2i = fd[0]
		var b: Vector2i = fd[fd.size() - 1]
		door_c = Vector2((float(a.x) + float(b.x) + 1.0) * 0.5, float(a.y))
		wall_y = a.y
		for pr in parts:
			if Rect2i(pr).has_point(a):
				door_part = pr
	var rows_free := (door_part.position.y - lot.position.y) if front == "N" else (lot.end.y - door_part.end.y)
	var awn_rect := Rect2()
	if not clear and not burnt:
		var porch := String(feat.get("porch", ""))
		if porch != "" and rows_free >= 1:
			var depth := mini(2, rows_free)
			var x0 := int(door_c.x) - 3
			var w := 6
			match porch:
				"stoop":
					x0 = int(door_c.x) - 2
					w = 4
				"portico":
					x0 = int(door_c.x) - 4
					w = 8
					depth = mini(3, rows_free)
				"wrap":
					x0 = door_part.position.x + 1
					w = maxi(6, door_part.size.x - 2)
			w = mini(w, door_part.size.x)
			x0 = clampi(x0, door_part.position.x, door_part.end.x - w)
			var py := (wall_y - depth) if front == "N" else (wall_y + 1)
			var pr_rect := Rect2(float(x0), float(py), float(w), float(depth))
			(fac.canopies as Array).append({"r": pr_rect, "kind": "porch" if porch in ["front", "wrap"] else porch, "dir": out_dir})
			var gname := "floor_hall" if porch == "portico" else "floor_wood"
			(out.ground as Array).append([Rect2i(x0, py, w, depth), gname])
			(out.keep as Array).append(Rect2i(x0, py, w, depth))
			features.append("porch:" + porch)
			if porch == "wrap" and depth >= 2:
				# a strip down one side, when the yard beside the house has the room
				var west_room := door_part.position.x - lot.position.x
				var east_room := lot.end.x - door_part.end.x
				var side_left := west_room >= 3 and (east_room < 3 or rng.randf() < 0.5)
				if side_left or east_room >= 3:
					var sx := (door_part.position.x - 2) if side_left else door_part.end.x
					var sh := mini(door_part.size.y - 1, 7)
					var sy := door_part.position.y if front == "N" else door_part.end.y - sh
					(fac.canopies as Array).append({"r": Rect2(float(sx), float(sy), 2.0, float(sh)), "kind": "porch", "dir": "w" if side_left else "e"})
					(out.ground as Array).append([Rect2i(sx, sy, 2, sh), "floor_wood"])
					(out.keep as Array).append(Rect2i(sx, sy, 2, sh))
		var awn := String(feat.get("awn", ""))
		if awn != "" and rows_free >= 1 and porch == "":
			if awn == "random":
				awn = AWNINGS[rng.randi() % AWNINGS.size()]
			var aw := clampi(door_part.size.x - 2, 4, 9)
			var ax := clampi(int(door_c.x - float(aw) * 0.5 + 0.5), door_part.position.x, maxi(door_part.position.x, door_part.end.x - aw))
			var adepth := mini(2, rows_free)
			var ay := (wall_y - adepth) if front == "N" else (wall_y + 1)
			awn_rect = Rect2(float(ax), float(ay), float(aw), float(adepth))
			(fac.canopies as Array).append({"r": awn_rect, "kind": "awn_" + awn, "dir": out_dir})
			features.append("awning")
		var canopy := String(feat.get("canopy", ""))
		if canopy != "":
			_canopy(ctx, canopy, out, fac, door_part, door_c, wall_y, rows_free, front, out_dir, rng, features)
		var icon := String(feat.get("sign", ""))
		if icon != "":
			if icon == "random":
				icon = SIGNS[rng.randi() % SIGNS.size()]
			var sy2 := float(wall_y) + (-0.4 if front == "N" else 1.4)
			var sx2 := door_c.x
			if awn_rect.size.x > 0.0:
				sy2 = awn_rect.position.y + awn_rect.size.y * 0.5
				sx2 = awn_rect.position.x + awn_rect.size.x * 0.5
			else:
				sx2 = door_c.x - 2.5 if rng.randf() < 0.5 else door_c.x + 3.0
			fac["sign"] = {"icon": icon, "x": sx2, "y": sy2}
			features.append("sign")
	for cn in fac.canopies:
		var cr: Rect2 = cn.r
		for xx in int(cr.size.x):
			for yy in int(cr.size.y):
				taken[Vector2i(int(cr.position.x) + xx, int(cr.position.y) + yy)] = true
	# ----- what stands on the roof
	if burnt:
		var cells: Array = []
		for pr in parts:
			var pq: Rect2i = pr
			for cy in range(1, pq.size.y - 1):
				for cx in range(1, pq.size.x - 1):
					cells.append(Vector2i(pq.position.x + cx, pq.position.y + cy))
		var nh := mini(cells.size() / 6, rng.randi_range(2, 5))
		for k in nh:
			var c: Vector2i = cells[rng.randi() % cells.size()]
			(fac.holes as Array).append(c)
		features.append("holes")
		return out
	var decor: Array = fac.decor
	var occupied := {}
	var has_chimney := false
	var main_style := String(styles[0])
	var chim_p := float(feat.get("chim", 0.0))
	if chim_p > 0.0 and rng.randf() < chim_p and main_style != "dome" and main_style != "glass" and main_style != "saw":
		var pq: Rect2i = main
		var wide := pq.size.x >= pq.size.y
		var pos := Vector2.ZERO
		if main_style == "gable" or main_style == "hip":
			var length := pq.size.x if wide else pq.size.y
			var t := rng.randf_range(0.2, 0.8)
			var along := float(pq.position.x if wide else pq.position.y) + float(length) * t
			var ridge := float(pq.position.y) + float(pq.size.y) * 0.5 if wide else float(pq.position.x) + float(pq.size.x) * 0.5
			pos = Vector2(along, ridge) if wide else Vector2(ridge, along)
		else:
			pos = Vector2(float(pq.position.x) + float(pq.size.x) * rng.randf_range(0.25, 0.75), float(pq.position.y) + float(pq.size.y) * rng.randf_range(0.3, 0.7))
		var cc := Vector2i(floori(pos.x), floori(pos.y))
		if not taken.has(cc):
			decor.append({"id": "chimney_%d" % (rng.randi() % 2), "x": pos.x, "y": pos.y, "k": 0.78})
			(fac.chimneys as Array).append(pos)
			occupied[cc] = true
			has_chimney = true
			features.append("chimney")
	var flat_parts: Array = []
	for pi in parts.size():
		if String(styles[pi]) == "flat":
			flat_parts.append(pi)
	var kind_big := kind in ["apartments", "office", "officeblock", "bank", "supermarket", "warehouse", "coldstore", "factory", "clinic", "police", "school", "cinema", "hall", "depot"]
	if not flat_parts.is_empty():
		var pq2: Rect2i = parts[flat_parts[0]]
		# air conditioners, vents, a skylight, a water tank
		var ac_p := float(feat.get("ac", 0.15))
		if rng.randf() < ac_p:
			var n_ac := rng.randi_range(1, 3 if kind_big else 2)
			for k in n_ac:
				var big := pq2.size.x >= 10 and rng.randf() < 0.4
				_place(decor, occupied, taken, pq2, "ac_big" if big else "ac_small", 1.5 if big else 0.75, rng)
			features.append("ac")
		for k in rng.randi_range(0, 2):
			_place(decor, occupied, taken, pq2, "vent_pipe" if rng.randf() < 0.6 else "roof_fan", 0.5, rng)
		if rng.randf() < 0.14 and pq2.size.x >= 5 and pq2.size.y >= 5:
			_place(decor, occupied, taken, pq2, "skylight", 1.0, rng)
			features.append("skylight")
		if kind_big and rng.randf() < 0.18 and pq2.size.x >= 8 and pq2.size.y >= 7:
			_place(decor, occupied, taken, pq2, "water_tank", 1.4, rng)
			features.append("tank")
		if bool(feat.get("mast", 0)):
			_place(decor, occupied, taken, pq2, "mast_dish", 1.5, rng)
			features.append("mast")
		if rng.randf() < float(feat.get("dish", 0.0)):
			_place(decor, occupied, taken, pq2, "dish", 0.75, rng)
			features.append("dish")
		if rng.randf() < float(feat.get("solar", 0.05)) and pq2.size.x >= 8 and pq2.size.y >= 6:
			_place(decor, occupied, taken, pq2, "solar_big", 2.0, rng)
			features.append("solar")
	else:
		var pq3: Rect2i = main
		if rng.randf() < float(feat.get("dish", 0.1)) * 0.5 + 0.04:
			_place(decor, occupied, taken, pq3, "dish", 0.75, rng)
			features.append("dish")
		if rng.randf() < float(feat.get("solar", 0.0)) + 0.06 and pq3.size.x >= 8:
			var wide3 := pq3.size.x >= pq3.size.y
			# on the sunny slope (the north one, or the west one of a part that is longer than wide)
			var sp := Vector2(float(pq3.position.x) + float(pq3.size.x) * rng.randf_range(0.3, 0.7), float(pq3.position.y) + float(pq3.size.y) * 0.25) if wide3 else Vector2(float(pq3.position.x) + float(pq3.size.x) * 0.25, float(pq3.position.y) + float(pq3.size.y) * rng.randf_range(0.3, 0.7))
			if main_style != "lean" and not taken.has(Vector2i(floori(sp.x), floori(sp.y))) and not occupied.has(Vector2i(floori(sp.x), floori(sp.y))):
				decor.append({"id": "solar", "x": sp.x, "y": sp.y})
				occupied[Vector2i(floori(sp.x), floori(sp.y))] = true
				features.append("solar")
		if rng.randf() < 0.08 and not has_chimney:
			_place(decor, occupied, taken, pq3, "aerial", 0.5, rng)
		if rng.randf() < 0.1:
			_place(decor, occupied, taken, pq3, "vent_pipe", 0.4, rng)
	# a tarp over a patch of a roof somebody mended (a few of the houses)
	if state != "ruined" and rng.randf() < 0.08 and not (main_style in ["flat", "dome", "glass", "saw"]):
		var pq4: Rect2i = main
		var tc := Vector2i(pq4.position.x + rng.randi_range(1, maxi(1, pq4.size.x - 2)), pq4.position.y + rng.randi_range(1, maxi(1, pq4.size.y - 2)))
		if not taken.has(tc) and not occupied.has(tc):
			(fac.tarps as Array).append(tc)
			fac["tarp_name"] = TARPS[rng.randi() % TARPS.size()]
			features.append("tarp")
	return out


## A thing somewhere on the roof of `part` (a cell not taken, not within a tile of the edge when the part is big enough): appended to `decor`.
static func _place(decor: Array, occupied: Dictionary, taken: Dictionary, part: Rect2i, id: String, w: float, rng: RandomNumberGenerator) -> bool:
	var inset := 1 if part.size.x >= 5 and part.size.y >= 5 else 0
	for attempt in 12:
		var cx := rng.randi_range(part.position.x + inset, part.end.x - 1 - inset)
		var cy := rng.randi_range(part.position.y + inset, part.end.y - 1 - inset)
		var c := Vector2i(cx, cy)
		var clash := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if occupied.has(Vector2i(cx + dx, cy + dy)):
					clash = true
		if clash or taken.has(c):
			continue
		var px := float(cx) + 0.5 + rng.randf_range(-0.15, 0.15)
		var py := float(cy) + 0.5 + rng.randf_range(-0.15, 0.15)
		decor.append({"id": id, "x": px, "y": py})
		occupied[c] = true
		if w > 1.1:
			occupied[Vector2i(cx + 1, cy)] = true
		return true
	return false


## The big covered things of a front: a gas station's canopy over its pumps, a carport, a loading dock's roof, a covered walk.
static func _canopy(ctx: Dictionary, canopy: String, out: Dictionary, fac: Dictionary, part: Rect2i, door_c: Vector2, wall_y: int, rows_free: int, front: String, out_dir: String, rng: RandomNumberGenerator, features: Array) -> void:
	var lot: Rect2i = ctx.lot
	match canopy:
		"gas":
			if rows_free < 7:
				return
			var w := mini(lot.size.x - 2, 12)
			var x0 := clampi(int(door_c.x) - w / 2, lot.position.x + 1, lot.end.x - 1 - w)
			var depth := 4
			var off := maxi(1, (rows_free - depth) / 2)
			var y0 := (lot.position.y + off) if front == "N" else (lot.end.y - off - depth)
			(fac.canopies as Array).append({"r": Rect2(float(x0), float(y0), float(w), float(depth)), "kind": "gas", "dir": out_dir})
			(out.keep as Array).append(Rect2i(x0, y0, w, depth))
			# the forecourt: asphalt from the street to the building
			var fy0 := lot.position.y if front == "N" else part.end.y
			(out.ground as Array).append([Rect2i(lot.position.x, fy0, lot.size.x, rows_free), "asphalt"])
			(out.keep as Array).append(Rect2i(lot.position.x, fy0, lot.size.x, rows_free))
			var mid_y := y0 + 1 if front == "N" else y0 + 2
			for k in 2:
				(out.props as Array).append({"kind": "gas_pump", "at": Vector2i(x0 + w / 2 - 2 + k * 3, mid_y)})
			features.append("canopy:gas")
		"carport":
			var west_room := part.position.x - lot.position.x
			var east_room := lot.end.x - part.end.x
			var left := west_room >= 5 and (east_room < 5 or rng.randf() < 0.5)
			if not left and east_room < 5:
				return
			var cx0 := (part.position.x - 5) if left else (part.end.x + 1)
			var cy0 := part.position.y if front == "N" else part.end.y - 4
			(fac.canopies as Array).append({"r": Rect2(float(cx0), float(cy0), 5.0, 4.0), "kind": "carport", "dir": "w" if left else "e"})
			(out.ground as Array).append([Rect2i(cx0, cy0, 5, 4), "gravel"])
			(out.keep as Array).append(Rect2i(cx0, cy0, 5, 4))
			(out.props as Array).append({"kind": "car_h", "at": Vector2i(cx0, cy0 + 1)})
			features.append("canopy:carport")
		"dock":
			if rows_free < 3:
				return
			var dw := mini(part.size.x - 2, 12)
			var dx0 := clampi(int(door_c.x) - dw / 2, part.position.x + 1, part.end.x - 1 - dw)
			var dy0 := (wall_y - 3) if front == "N" else (wall_y + 1)
			(fac.canopies as Array).append({"r": Rect2(float(dx0), float(dy0), float(dw), 3.0), "kind": "dock", "dir": out_dir})
			(out.ground as Array).append([Rect2i(dx0, dy0, dw, 3), "sidewalk"])
			(out.keep as Array).append(Rect2i(dx0, dy0, dw, 3))
			features.append("canopy:dock")
		"walk":
			if rows_free < 2:
				return
			var ww := part.size.x
			var wy0 := (wall_y - 2) if front == "N" else (wall_y + 1)
			(fac.canopies as Array).append({"r": Rect2(float(part.position.x), float(wy0), float(ww), 2.0), "kind": "walk", "dir": out_dir})
			(out.ground as Array).append([Rect2i(part.position.x, wy0, ww, 2), "sidewalk"])
			(out.keep as Array).append(Rect2i(part.position.x, wy0, ww, 2))
			features.append("canopy:walk")
