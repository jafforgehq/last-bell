## The paint of one roof (WORLD3): which picture goes in which cell of a building's roofs, from the building's FACADE (scripts/town/building_facade.gd, `house.facade`). The kit has one roof, a gable of
## two slopes with a ridge cap; a facade gives each PART its own: "gable" (the kit's, ridge along the longer side), "hip" (four slopes, a short ridge, the diagonals shaded), "lean" (one slope that falls
## to `dir`), "flat" (a fill and the parapet along its edge), "saw" (a sawtooth: rows of glass and metal), "dome" (a silo's round cap on a concrete deck), "glass" (a greenhouse: panes that let the inside
## show) and, for a house that burnt, "burnt" (charred shingles with holes and rubble). A colour (`tint_id`: the kit's pictures multiplied, scripts/render/roof_look.gd), tarps over a few cells, the
## things that stand on a roof (chimneys, air conditioners, dishes, solar panels, skylights, vents), and on the front the awnings, porches, canopies and the sign.
##
## All the pictures are cut from the one atlas (scripts/render/roof_atlas.gd): the result is a list of draw commands, in the order they are laid: fills, ridge caps, eaves (the kit's overlay on the border
## cells), then what stands on the roof and what hangs off the front. A roof with no facade is a plain gable of its kit's colour, as every roof was before WORLD3.
extends RefCounted

const RoofAtlas := preload("res://scripts/render/roof_atlas.gd")
const RoofLook := preload("res://scripts/render/roof_look.gd")

const TILE := 64.0
## How far the awnings and canopies are see-through (the people under them show).
const CANOPY_ALPHA := 0.84
const GLASS_ALPHA := 0.6
## The canopies by kind: the fill, whether it has posts, a band along its outer edge, how see-through.
const CANOPY := {
	"porch": {"fill": "porch_shingle", "posts": 1, "band": "", "a": 0.88}, "stoop": {"fill": "porch_shingle", "posts": 1, "band": "", "a": 0.88},
	"portico": {"fill": "flat_concrete", "posts": 2, "band": "", "a": 0.9}, "gas": {"fill": "canopy_white", "posts": 1, "band": "canopy_band", "a": 0.86},
	"carport": {"fill": "metal_rib_h", "posts": 1, "band": "", "a": 0.86}, "dock": {"fill": "flat_metal", "posts": 1, "band": "", "a": 0.86},
	"walk": {"fill": "flat_metal", "posts": 1, "band": "", "a": 0.86}, "pergola": {"fill": "pergola", "posts": 1, "band": "", "a": 1.0},
}


## The draw commands of a roof, in order: `dst` (x, y, w, h in pixels of the roof node), `src` (the same in the atlas), `col`, `tr` (the picture drawn turned a quarter).
class Cmds:
	var n := 0
	var dst := PackedFloat32Array()
	var src := PackedFloat32Array()
	var col := PackedColorArray()
	var tr := PackedByteArray()

	func add(d: Rect2, s: Rect2, c: Color, t: bool = false) -> void:
		dst.push_back(d.position.x)
		dst.push_back(d.position.y)
		dst.push_back(d.size.x)
		dst.push_back(d.size.y)
		src.push_back(s.position.x)
		src.push_back(s.position.y)
		src.push_back(s.size.x)
		src.push_back(s.size.y)
		col.push_back(c)
		tr.push_back(1 if t else 0)
		n += 1

	func append(o: Cmds) -> void:
		dst.append_array(o.dst)
		src.append_array(o.src)
		col.append_array(o.col)
		tr.append_array(o.tr)
		n += o.n


static var _src_cache := {}


static func _src(set: Dictionary, d: Dictionary) -> Rect2:
	return RoofAtlas.rect_for(set, d, Rect2(d.get("rect", Rect2())))


static func _has_cells(cells: Dictionary, c: Vector2i) -> bool:
	return cells.has(c)


## The commands of the roof of a building: `rect` its bounding box (tiles), `tiles` the kit's pieces (`TownArt.roof(...).tiles`), `set` the atlas, `notches` [[tiles, side]] of the outside doors,
## `parts` its rectangles, `fac` its facade ({} for the kit's plain gable), `kit` 0 terracotta, 1 slate, 2 shingle.
static func build(id: int, rect: Rect2i, tiles: Dictionary, set: Dictionary, notches: Array, parts: Array, fac: Dictionary, kit: int) -> Cmds:
	var fills := Cmds.new()
	var caps := Cmds.new()
	var edges := Cmds.new()
	var over := Cmds.new()
	var lit: Array = tiles.lit
	var shade: Array = tiles.shade
	var ridge: Dictionary = tiles.ridge
	var edge: Dictionary = tiles.edge
	var plist: Array = parts if parts.size() > 0 else [rect]
	var open := {}
	for n in notches:
		for t in n[0]:
			open[Vector2i(t.x - rect.position.x, t.y - rect.position.y)] = true
	var cells := {}
	for pr in plist:
		var pq: Rect2i = pr
		for cy in pq.size.y:
			for cx in pq.size.x:
				cells[Vector2i(pq.position.x - rect.position.x + cx, pq.position.y - rect.position.y + cy)] = true
	var has_x := RoofAtlas.has_extras(set)
	var state := String(fac.get("state", ""))
	var charred := state == "burnt" and has_x
	var styles: Array = fac.get("styles", [])
	var dirs: Array = fac.get("dirs", [])
	var levels: Array = fac.get("levels", [])
	var main_style := String(fac.get("style", "gable"))
	var tint_main := RoofLook.tint(kit, -1 if charred else int(fac.get("tint_id", 0)))
	var flat_name := String(fac.get("flat", "flat_tar"))
	var done := {}
	var white := Color.WHITE
	var piece := Vector2(TILE, TILE)
	for pi in plist.size():
		var pq: Rect2i = plist[pi]
		var style := String(styles[pi]) if pi < styles.size() else main_style
		if charred:
			style = "burnt"
		elif not has_x and not (style in ["gable", "hip", "lean"]):
			style = "gable"
		var tint := tint_main
		if pi < levels.size() and int(levels[pi]) > 0 and not charred:
			tint = Color(tint.r * 0.86, tint.g * 0.86, tint.b * 0.88)
		var dir := String(dirs[pi]) if pi < dirs.size() else "s"
		var ox := pq.position.x - rect.position.x
		var oy := pq.position.y - rect.position.y
		var w := pq.size.x
		var h := pq.size.y
		var wide := w >= h
		var part_cells: Array = []
		for cy in h:
			for cx in w:
				var gc := Vector2i(ox + cx, oy + cy)
				if open.has(gc) or done.has(gc):
					continue
				done[gc] = true
				part_cells.append(Vector2i(cx, cy))
				var cell := Rect2(Vector2(gc) * TILE, piece)
				var variant := 1 if posmod(gc.x * 73 + gc.y * 31 + id * 17, 8) == 0 else 0
				match style:
					"hip":
						var dn := cy
						var ds := h - 1 - cy
						var dw := cx
						var de := w - 1 - cx
						var m := mini(mini(dn, ds), mini(dw, de))
						var zone := 0
						if wide:
							zone = 0 if m == dn else (1 if m == ds else (2 if m == dw else 3))
						else:
							zone = 2 if m == dw else (3 if m == de else (0 if m == dn else 1))
						var is_lit := zone == 0 or zone == 2
						var d: Dictionary = (lit if is_lit else shade)[variant]
						fills.add(cell, _src(set, d), tint, zone >= 2)
					"lean":
						var is_lit2 := dir == "n" or dir == "w"
						var d2: Dictionary = (lit if is_lit2 else shade)[variant]
						fills.add(cell, _src(set, d2), tint, dir == "e" or dir == "w")
					"flat":
						fills.add(cell, RoofAtlas.extra(set, flat_name), white)
					"saw":
						if cy % 3 == 0:
							fills.add(cell, RoofAtlas.extra(set, "glass"), Color(1, 1, 1, 0.92))
						else:
							fills.add(cell, RoofAtlas.extra(set, "metal_rib_h"), white)
					"dome":
						fills.add(cell, RoofAtlas.extra(set, "flat_concrete"), white)
					"glass":
						fills.add(cell, RoofAtlas.extra(set, "glass"), Color(1, 1, 1, GLASS_ALPHA))
					"burnt":
						fills.add(cell, RoofAtlas.extra(set, "burnt"), white)
					_:
						var slope := (cy if wide else cx) < (((h if wide else w) + 1) >> 1)
						var dg: Dictionary = (lit if slope else shade)[variant]
						fills.add(cell, _src(set, dg), tint, not wide)
		# the ridge
		match style:
			"gable":
				var rows := h if wide else w
				var line := (rows >> 1) - 1 if rows % 2 == 0 else rows >> 1
				var off := 0.5 if rows % 2 == 0 else 0.0
				var cap: Dictionary = ridge.get("h" if wide else "v", ridge.values()[0])
				for i in (w if wide else h):
					var c := Vector2i(ox + i, oy + line) if wide else Vector2i(ox + line, oy + i)
					if open.has(c):
						continue
					var at := Vector2(c) * TILE + (Vector2(0, off * TILE) if wide else Vector2(off * TILE, 0))
					caps.add(Rect2(at, piece), _src(set, cap), tint, false)
			"hip":
				var rows2 := h if wide else w
				var line2 := (rows2 >> 1) - 1 if rows2 % 2 == 0 else rows2 >> 1
				var off2 := 0.5 if rows2 % 2 == 0 else 0.0
				var inset := rows2 >> 1
				var cap2: Dictionary = ridge.get("h" if wide else "v", ridge.values()[0])
				var length := (w if wide else h)
				var from_i := inset
				var to_i := length - 1 - inset
				if to_i < from_i:
					from_i = length >> 1
					to_i = from_i
				for i in range(from_i, to_i + 1):
					var c2 := Vector2i(ox + i, oy + line2) if wide else Vector2i(ox + line2, oy + i)
					if open.has(c2):
						continue
					var at2 := Vector2(c2) * TILE + (Vector2(0, off2 * TILE) if wide else Vector2(off2 * TILE, 0))
					caps.add(Rect2(at2, piece), _src(set, cap2), tint, false)
			"lean":
				var cap3: Dictionary = ridge.get("v" if (dir == "e" or dir == "w") else "h", ridge.values()[0])
				var n_ridge := h if (dir == "e" or dir == "w") else w
				for i in n_ridge:
					var c3 := Vector2i.ZERO
					match dir:
						"s":
							c3 = Vector2i(ox + i, oy)
						"n":
							c3 = Vector2i(ox + i, oy + h - 1)
						"e":
							c3 = Vector2i(ox, oy + i)
						_:
							c3 = Vector2i(ox + w - 1, oy + i)
					if open.has(c3):
						continue
					caps.add(Rect2(Vector2(c3) * TILE, piece), _src(set, cap3), tint, false)
			"flat":
				# the parapet along the edge of the part, where no roof of the building is next to it
				var par_h := RoofAtlas.extra(set, "parapet_h")
				var par_v := RoofAtlas.extra(set, "parapet_v")
				var th := TILE * (par_h.size.y / 128.0)
				for pc in part_cells:
					var gc2 := Vector2i(ox + pc.x, oy + pc.y)
					var p0 := Vector2(gc2) * TILE
					if not cells.has(gc2 + Vector2i(0, -1)) or open.has(gc2 + Vector2i(0, -1)):
						edges.add(Rect2(p0, Vector2(TILE, th)), par_h, white)
					if not cells.has(gc2 + Vector2i(0, 1)) or open.has(gc2 + Vector2i(0, 1)):
						edges.add(Rect2(p0 + Vector2(0, TILE - th), Vector2(TILE, th)), par_h, white)
					if not cells.has(gc2 + Vector2i(-1, 0)) or open.has(gc2 + Vector2i(-1, 0)):
						edges.add(Rect2(p0, Vector2(th, TILE)), par_v, white)
					if not cells.has(gc2 + Vector2i(1, 0)) or open.has(gc2 + Vector2i(1, 0)):
						edges.add(Rect2(p0 + Vector2(TILE - th, 0), Vector2(th, TILE)), par_v, white)
			"dome":
				var dome := RoofAtlas.extra(set, "dome")
				var ctr := (Vector2(ox, oy) + Vector2(w, h) * 0.5) * TILE
				var sz := Vector2(w, h) * TILE
				over.add(Rect2(ctr - sz * 0.5, sz), dome, white)
	# holes and tarps
	for hc in fac.get("holes", []):
		var rc := Vector2i(int(hc.x) - rect.position.x, int(hc.y) - rect.position.y)
		if done.has(rc):
			fills.add(Rect2(Vector2(rc) * TILE, piece), RoofAtlas.extra(set, "hole" if (rc.x + rc.y) % 2 == 0 else "rubble"), white)
	if not charred:
		for tc in fac.get("tarps", []):
			var tr_c := Vector2i(int(tc.x) - rect.position.x, int(tc.y) - rect.position.y)
			if done.has(tr_c):
				fills.add(Rect2(Vector2(tr_c) * TILE, piece), RoofAtlas.extra(set, String(fac.get("tarp_name", "tarp_blue"))), white)
	# the eave: the kit's overlay on the cells that have no roof next to them
	var cell_px: Vector2 = edge.cell
	var span := cell_px / 224.0 * 1.75 * TILE
	for gc3 in done:
		var cx3: int = gc3.x
		var cy3: int = gc3.y
		var mask := 0
		if not cells.has(Vector2i(cx3, cy3 - 1)) or open.has(Vector2i(cx3, cy3 - 1)):
			mask |= 1
		if not cells.has(Vector2i(cx3 + 1, cy3)) or open.has(Vector2i(cx3 + 1, cy3)):
			mask |= 2
		if not cells.has(Vector2i(cx3, cy3 + 1)) or open.has(Vector2i(cx3, cy3 + 1)):
			mask |= 4
		if not cells.has(Vector2i(cx3 - 1, cy3)) or open.has(Vector2i(cx3 - 1, cy3)):
			mask |= 8
		if mask == 0:
			continue
		var s0 := Rect2(Rect2(edge.rect).position + Vector2(mask % int(edge.cols), mask / int(edge.cols)) * cell_px, cell_px)
		edges.add(Rect2(Vector2(cx3, cy3) * TILE - Vector2(0.25, 0.25) * TILE, span), RoofAtlas.rect_for(set, edge, s0), white)
	# what stands on the roof
	if has_x:
		for dc in fac.get("decor", []):
			var name := String(dc.id)
			var src := RoofAtlas.extra(set, name)
			if src.size.x <= 0.0:
				continue
			var tl: Vector2 = (set.get("etiles", {}) as Dictionary).get(name, Vector2.ONE)
			var scale_k := float(dc.get("k", 1.0))
			var size := tl * TILE * scale_k
			var at_c := (Vector2(float(dc.x), float(dc.y)) - Vector2(rect.position)) * TILE
			over.add(Rect2(at_c - size * 0.5, size), src, white)
		# the fronts: porches, canopies, awnings
		for cn in fac.get("canopies", []):
			_canopy(over, set, rect, cn)
		var sg: Dictionary = fac.get("sign", {})
		if not sg.is_empty():
			var ssrc := RoofAtlas.extra(set, "sign_" + String(sg.icon))
			if ssrc.size.x > 0.0:
				var sc := (Vector2(float(sg.x), float(sg.y)) - Vector2(rect.position)) * TILE
				var ss := Vector2(0.78, 0.78) * TILE
				over.add(Rect2(sc - ss * 0.5, ss), ssrc, white)
	var out := Cmds.new()
	out.append(fills)
	out.append(caps)
	out.append(edges)
	out.append(over)
	return out


## An awning or a canopy: `cn` {"r": Rect2 (tiles), "kind", "dir" (the way out from the wall: "n", "s", "e", "w")}.
static func _canopy(over: Cmds, set: Dictionary, rect: Rect2i, cn: Dictionary) -> void:
	var r: Rect2 = cn.r
	var kind := String(cn.kind)
	var dir := String(cn.get("dir", "s"))
	var origin := (r.position - Vector2(rect.position)) * TILE
	var white := Color.WHITE
	if kind.begins_with("awn_"):
		var src := RoofAtlas.extra(set, "awning_" + kind.substr(4))
		if src.size.x <= 0.0:
			return
		var col := Color(1, 1, 1, CANOPY_ALPHA)
		# each tile of the front a stripe of the awning, stretched to its depth; the lip at the outer edge
		var horizontal := dir == "n" or dir == "s"
		var count := int(r.size.x) if horizontal else int(r.size.y)
		for i in count:
			if horizontal:
				var d := Rect2(origin + Vector2(float(i) * TILE, 0), Vector2(TILE, r.size.y * TILE))
				if dir == "n":
					d = Rect2(d.position + Vector2(0, d.size.y), Vector2(d.size.x, -d.size.y))
				over.add(d, src, col, false)
			else:
				var d2 := Rect2(origin + Vector2(0, float(i) * TILE), Vector2(r.size.x * TILE, TILE))
				over.add(d2, src, col, true)
		return
	var spec: Dictionary = CANOPY.get(kind, CANOPY.porch)
	var fill := RoofAtlas.extra(set, String(spec.fill))
	if fill.size.x <= 0.0:
		return
	var col2 := Color(1, 1, 1, float(spec.a))
	for cy in int(r.size.y):
		for cx in int(r.size.x):
			over.add(Rect2(origin + Vector2(cx, cy) * TILE, Vector2(TILE, TILE)), fill, col2)
	var band := String(spec.band)
	if band != "":
		var bh := RoofAtlas.extra(set, band + "_h")
		var bv := RoofAtlas.extra(set, band + "_v")
		var th := TILE * (bh.size.y / 128.0)
		var sz := r.size * TILE
		for cx in int(r.size.x):
			over.add(Rect2(origin + Vector2(cx * TILE, 0), Vector2(TILE, th)), bh, white)
			over.add(Rect2(origin + Vector2(cx * TILE, sz.y - th), Vector2(TILE, th)), bh, white)
		for cy in int(r.size.y):
			over.add(Rect2(origin + Vector2(0, cy * TILE), Vector2(th, TILE)), bv, white)
			over.add(Rect2(origin + Vector2(sz.x - th, cy * TILE), Vector2(th, TILE)), bv, white)
	if int(spec.posts) > 0:
		var post := RoofAtlas.extra(set, "post")
		if post.size.x > 0.0:
			var ps := Vector2(0.3125, 0.3125) * TILE * float(spec.posts)
			var sz2 := r.size * TILE
			var inset := ps * 0.7
			var spots: Array = [Vector2(inset.x, inset.y), Vector2(sz2.x - inset.x, inset.y), Vector2(inset.x, sz2.y - inset.y), Vector2(sz2.x - inset.x, sz2.y - inset.y)]
			# (a long canopy has a post every four tiles along its outer edge)
			var along_x := dir == "n" or dir == "s"
			var n_mid := int((r.size.x if along_x else r.size.y) / 4.0)
			for k in range(1, n_mid + 1):
				var f := float(k) / float(n_mid + 1)
				if along_x:
					spots.append(Vector2(sz2.x * f, inset.y if dir == "n" else sz2.y - inset.y))
				else:
					spots.append(Vector2(inset.x if dir == "w" else sz2.x - inset.x, sz2.y * f))
			for sp in spots:
				over.add(Rect2(origin + sp - ps * 0.5, ps), post, white)
