## The roofs of the town (feature/town-core): one roof for each house, over its walls' rectangle, above the people and the dead (z 7), so that what is inside a house
## is hidden until the avatar is. `update(house_id, dt)` is told which house the avatar stands in (-1: none): that roof fades out over FADE seconds, the others
## are shut; a roof that is clear is not visible at all (it costs nothing).
##
## MODES: "house" (default) a MeshInstance2D for each house (an off-screen roof is culled by the renderer: a draw call for each roof on screen);
## "multi" ONE MultiMeshInstance2D for all of them (one draw call whatever is on screen, the fade is the instance colour: scripts/town/town_roofs.gdshader
## puts the texture on by the world's place so that a roof of any size repeats the atlas as the ground does); "off" none.
## PAINTED ROOFS (2026-10-17, "roofs look weird"): in "house" mode every roof is code-drawn in the RimWorld manner, flat colours, a dark outline, the light from the north west (north and west
## faces lit, south and east faces in shade, a shadow cast to the south east), no tiled texture:
##   a generated house (its `facade`, scripts/town/building_facade.gd) by `paint_house`: each part a gable, hip or lean-to whose ridge and hips follow the footprint (a wing of an L, T or U
##   meets the main roof in two valleys), or a flat deck with its parapet (also saw-tooth, dome and glass), courses on the slopes, a ridge cap, a gutter line, a little wear, then the facade's
##   chimneys, tarps, holes, rooftop things, porches, awnings and sign (the kit's pictures, scripts/render/roof_atlas.gd);
##   a raid site's building (`roof_look` {sign, tint, trim, n}, scripts/prison/prison_site.gd) by `paint_look`: a flat deck with the parapet trim, panel seams, units chosen by the building's kind
##   (air conditioners, vents, skylights, fans, a mast) and a painted sign (a red cross, a word, a number).
## A house with neither keeps the old placeholder: the ROOF and ROOF_LIGHT ground textures of the base map.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const RoofAtlas := preload("res://scripts/render/roof_atlas.gd")
const RoofLook := preload("res://scripts/render/roof_look.gd")
const RoofPaint := preload("res://scripts/render/roof_paint.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const TILE := GD.TILE
const FADE := 0.25
const Z := 7

var mode := "house"
var houses: Array = []
var _nodes: Array = []
var _alpha := PackedFloat32Array()
var _target := PackedFloat32Array()
var _multi: MultiMeshInstance2D
var _mm: MultiMesh
var _first := PackedInt32Array()
var _count := PackedInt32Array()
var _dirty := false
var inside := -1
## How many roofs are not clear now (for the overlay).
var shown := 0
## The roof kit's atlas (the pictures of the things on a roof), shared by every town of the run; made at the first house that needs it.
static var _atlas = null
static var _set = null


func setup(town: Dictionary, data: Dictionary, roof_mode: String = "house") -> void:
	mode = roof_mode
	houses = town.houses
	z_index = Z
	_alpha.resize(houses.size())
	_alpha.fill(1.0)
	_target.resize(houses.size())
	_target.fill(1.0)
	if mode == "off":
		return
	var tex_a: Texture2D = GD.tex(String(data.terrainTypes.ROOF.file))
	var tex_b: Texture2D = GD.tex(String(data.terrainTypes.ROOF_LIGHT.file))
	if mode == "multi":
		_setup_multi(tex_a)
		return
	for h in houses:
		var fac = h.get("facade")
		var look = h.get("roof_look")
		if look is Dictionary or (fac is Dictionary and not (fac as Dictionary).is_empty()):
			var dn := DrawNode.new()
			dn.name = "Roof%d" % int(h.id)
			if look is Dictionary:
				dn.painter = func(c): paint_look(c, h)
			else:
				dn.painter = func(c): paint_house(c, h, _atlas_set())
			add_child(dn)
			_nodes.append(dn)
			continue
		var tex: Texture2D = tex_a if int(h.id) % 3 != 0 else tex_b
		var piece_uv := Vector2(128.0 / float(tex.get_width()), 128.0 / float(tex.get_height()))
		# one quad for each part of the house (a building of several parts: an L, a T...)
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for pr in _parts_of(h):
			var r: Rect2i = pr
			var a := Vector2(r.position)
			var b := Vector2(r.end)
			var k := verts.size()
			verts.append_array(PackedVector2Array([a * TILE, Vector2(b.x, a.y) * TILE, b * TILE, Vector2(a.x, b.y) * TILE]))
			uvs.append_array(PackedVector2Array([a * piece_uv, Vector2(b.x, a.y) * piece_uv, b * piece_uv, Vector2(a.x, b.y) * piece_uv]))
			idx.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance2D.new()
		mi.name = "Roof%d" % int(h.id)
		mi.mesh = mesh
		mi.texture = tex
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(mi)
		_nodes.append(mi)
	shown = houses.size()


## The rectangles of a house's roofs: its `parts`, else its rectangle.
static func _parts_of(h: Dictionary) -> Array:
	var ps = h.get("parts")
	return ps if (ps is Array and not ps.is_empty()) else [h.rect]


func _setup_multi(tex: Texture2D) -> void:
	var quad := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.mesh = quad
	# one instance for each part of each house (the first instance of a house is `_first[id]`, `_count[id]` of them)
	var total := 0
	for h in houses:
		total += _parts_of(h).size()
	_mm.instance_count = total
	_first.resize(houses.size())
	_count.resize(houses.size())
	var k := 0
	for h in houses:
		_first[int(h.id)] = k
		var ps := _parts_of(h)
		_count[int(h.id)] = ps.size()
		for pr in ps:
			var r: Rect2i = pr
			var t := Transform2D(0.0, Vector2(float(r.size.x), float(r.size.y)) * TILE, 0.0, Vector2(r.position) * TILE)
			_mm.set_instance_transform_2d(k, t)
			_mm.set_instance_color(k, Color(1, 1, 1, 1))
			k += 1
	_multi = MultiMeshInstance2D.new()
	_multi.name = "Roofs"
	_multi.multimesh = _mm
	_multi.texture = tex
	_multi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/town/town_roofs.gdshader")
	_multi.material = mat
	add_child(_multi)
	shown = houses.size()


## The avatar stands in `house_id` (-1 outside every house): its roof opens.
func update(house_id: int, dt: float) -> void:
	if mode == "off" or houses.is_empty():
		return
	if house_id != inside:
		if inside >= 0:
			_target[inside] = 1.0
		if house_id >= 0:
			_target[house_id] = 0.0
		inside = house_id
		_dirty = true
	if not _dirty:
		return
	var step := dt / FADE
	var moving := false
	var open := 0
	for i in houses.size():
		var a := _alpha[i]
		var t := _target[i]
		if a != t:
			a = move_toward(a, t, step)
			_alpha[i] = a
			_apply(i, a)
			if a != t:
				moving = true
		if a > 0.0:
			open += 1
	shown = open
	_dirty = moving


func _apply(i: int, a: float) -> void:
	if mode == "multi":
		for k in _count[i]:
			_mm.set_instance_color(_first[i] + k, Color(1, 1, 1, a))
		return
	var n: CanvasItem = _nodes[i]
	n.visible = a > 0.01
	n.modulate.a = a


# ------------------------------------------------------------------ the painted roofs --

const OUTLINE := Color(0.13, 0.1, 0.08)
const UNIT_GREY := Color(0.62, 0.64, 0.64)
const GLASS := Color(0.43, 0.6, 0.72)
## Where a roof's shadow falls on the ground (the light is from the north west).
const SHADOW_OFF := Vector2(11.0, 15.0)
const SHADOW := Color(0, 0, 0, 0.24)
## The slopes' colours by kit: terracotta, slate, shingle (multiplied by the facade's tint, scripts/render/roof_look.gd).
const KIT_COL := [Color(0.68, 0.34, 0.25), Color(0.36, 0.40, 0.47), Color(0.45, 0.38, 0.31)]
## The courses of a slope (px apart) by kit.
const COURSE := [10.0, 13.0, 11.0]
## How bright a slope is by the way it faces.
const FACE_K := {"n": 1.1, "w": 1.0, "e": 0.86, "s": 0.78}
## The decks of the flat roofs by the facade's `flat` fill.
const DECK := {"flat_tar": Color(0.31, 0.31, 0.32), "flat_gravel": Color(0.5, 0.49, 0.46), "flat_concrete": Color(0.66, 0.65, 0.62), "flat_green": Color(0.38, 0.47, 0.37),
	"flat_sand": Color(0.66, 0.6, 0.47), "flat_metal": Color(0.53, 0.56, 0.58)}
const TARP := {"tarp_blue": Color(0.25, 0.43, 0.66), "tarp_green": Color(0.32, 0.48, 0.3), "tarp_orange": Color(0.86, 0.5, 0.2)}
## The deck tones of a raid site's building (the old placeholder textures' average: dark tar, light concrete), multiplied by its look's tint.
const SITE_DARK := Color(0.3, 0.3, 0.31)
const SITE_LIGHT := Color(0.7, 0.68, 0.65)
const PAR := 10.0


static func _atlas_set():
	if _atlas == null:
		_atlas = RoofAtlas.new()
		var tiles = TownArt.roof("", 0).get("tiles")
		_set = _atlas.for_tiles(tiles) if tiles is Dictionary else null
	return _set


static func _k(c: Color, f: float) -> Color:
	return Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0), c.a)


static func _rect_px(r: Rect2i) -> Rect2:
	return Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)


static func _poly_of(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## The outline(s) of a set of rectangles that touch edge to edge (holes left out).
static func _union(rects: Array) -> Array:
	var polys: Array = []
	for r in rects:
		var p := _poly_of(r)
		var merged := false
		for k in polys.size():
			var res: Array = Geometry2D.merge_polygons(polys[k], p)
			var outer: Array = res.filter(func(q): return not Geometry2D.is_polygon_clockwise(q))
			if outer.size() == 1:
				polys[k] = outer[0]
				merged = true
				break
		if not merged:
			polys.append(p)
	return polys


static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


static func _style(styles: Array, i: int, main_style: String) -> String:
	return String(styles[i]) if i < styles.size() else main_style


## The roof plan of a building: its parts in the order they are drawn, each {"i" part index, "r" Rect2 px (trimmed off the part it joins), "x" ridge along x, "ha"/"hb" a hip at the
## start/end of the ridge, "ea"/"eb" how far the ridge runs on into the roof it joins (the valleys), "to" the plan index it joins or -1}. The main part (the biggest) comes first; a wing
## that meets it along a whole side of its own gets its ridge across that side, so an L, a T or a U reads as one roof.
static func plan_of(parts: Array, styles: Array, main_style: String) -> Array:
	var n := parts.size()
	var main := 0
	for i in n:
		if (parts[i] as Rect2i).get_area() > (parts[main] as Rect2i).get_area():
			main = i
	var m: Rect2i = parts[main]
	var mh := _style(styles, main, main_style) == "hip"
	var out: Array = [{"i": main, "r": _rect_px(m), "x": m.size.x >= m.size.y, "ha": mh, "hb": mh, "ea": 0.0, "eb": 0.0, "to": -1}]
	for i in n:
		if i == main:
			continue
		var r: Rect2i = parts[i]
		var st := _style(styles, i, main_style)
		var hip := st == "hip"
		var rec := {"i": i, "r": _rect_px(r), "x": r.size.x >= r.size.y, "ha": hip, "hb": hip, "ea": 0.0, "eb": 0.0, "to": -1}
		for j in out.size():
			var q: Rect2i = parts[int(out[j].i)]
			var it := r.intersection(q)
			if not it.has_area():
				continue
			var side := ""
			if it.size.y == r.size.y and it.size.x < r.size.x:
				side = "w" if it.position.x == r.position.x else "e"
			elif it.size.x == r.size.x and it.size.y < r.size.y:
				side = "n" if it.position.y == r.position.y else "s"
			if side == "":
				continue
			var t := r
			match side:
				"w":
					t = Rect2i(r.position.x + it.size.x, r.position.y, r.size.x - it.size.x, r.size.y)
				"e":
					t = Rect2i(r.position.x, r.position.y, r.size.x - it.size.x, r.size.y)
				"n":
					t = Rect2i(r.position.x, r.position.y + it.size.y, r.size.x, r.size.y - it.size.y)
				_:
					t = Rect2i(r.position.x, r.position.y, r.size.x, r.size.y - it.size.y)
			rec.r = _rect_px(t)
			rec.to = j
			rec.x = t.size.x >= t.size.y
			var across_x := side == "w" or side == "e"    # the wing's ridge runs along x when it meets on its west or east side
			var width := float(t.size.y if across_x else t.size.x)
			var depth := float(t.size.x if across_x else t.size.y)
			if depth >= width * 0.6 and st in ["gable", "hip", "burnt"]:
				rec.x = across_x
				var tq: Rect2 = out[j].r
				var ext := 0.0
				if _style(styles, int(out[j].i), main_style) in ["gable", "hip", "burnt"]:
					ext = minf(width * TILE * 0.5, (tq.size.x if across_x else tq.size.y) * 0.5)
				if side == "w" or side == "n":
					rec.ha = false
					rec.ea = ext
				else:
					rec.hb = false
					rec.eb = ext
			break
		out.append(rec)
	return out


## The slopes of a pitched part: [[polygon, facing "n"|"s"|"w"|"e"], ...], the ridge [a, b], the hips and the valleys (pairs of points).
static func _slopes(r: Rect2, along_x: bool, ha: bool, hb: bool, ea: float, eb: float) -> Dictionary:
	var q := r if along_x else Rect2(Vector2(r.position.y, r.position.x), Vector2(r.size.y, r.size.x))
	var x0 := q.position.x
	var x1 := q.end.x
	var y0 := q.position.y
	var y1 := q.end.y
	var half := q.size.y * 0.5
	var cy := y0 + half
	var ra := x0 + (half if ha else 0.0) - ea
	var rb := x1 - (half if hb else 0.0) + eb
	if ra > rb:
		ra = (ra + rb) * 0.5
		rb = ra
	var a := Vector2(ra, cy)
	var b := Vector2(rb, cy)
	var faces: Array = [[PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), b, a]), "n"], [PackedVector2Array([Vector2(x1, y1), Vector2(x0, y1), a, b]), "s"]]
	var hips: Array = []
	var valleys: Array = []
	if ha:
		faces.append([PackedVector2Array([Vector2(x0, y1), Vector2(x0, y0), a]), "w"])
		hips.append_array([Vector2(x0, y0), a, Vector2(x0, y1), a])
	elif ea > 0.0:
		valleys.append_array([Vector2(x0, y0), a, Vector2(x0, y1), a])
	if hb:
		faces.append([PackedVector2Array([Vector2(x1, y0), Vector2(x1, y1), b]), "e"])
		hips.append_array([Vector2(x1, y0), b, Vector2(x1, y1), b])
	elif eb > 0.0:
		valleys.append_array([Vector2(x1, y0), b, Vector2(x1, y1), b])
	var ridge: Array = [a, b]
	if not along_x:
		var flip := {"n": "w", "s": "e", "w": "n", "e": "s"}
		for f in faces:
			var p: PackedVector2Array = f[0]
			for k in p.size():
				p[k] = Vector2(p[k].y, p[k].x)
			f[0] = p
			f[1] = flip[f[1]]
		for arr in [hips, valleys, ridge]:
			for k in arr.size():
				arr[k] = Vector2(arr[k].y, arr[k].x)
	return {"faces": faces, "ridge": ridge, "hips": hips, "valleys": valleys}


## One slope: its colour by the way it faces, the courses parallel to its eave, kept inside it.
static func _slope(c: CanvasItem, poly: PackedVector2Array, facing: String, col: Color, course: float) -> void:
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return
	var fc := _k(col, float(FACE_K[facing]))
	c.draw_colored_polygon(poly, fc)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var horiz := facing == "n" or facing == "s"
	var down := facing == "s" or facing == "e"    # (the courses start at the eave: the low edge)
	var span := (hi.y - lo.y) if horiz else (hi.x - lo.x)
	var lines := PackedVector2Array()
	var d := course
	while d < span - 3.0:
		var t := ((hi.y - d) if down else (lo.y + d)) if horiz else ((hi.x - d) if down else (lo.x + d))
		var seg := PackedVector2Array([Vector2(lo.x - 2.0, t), Vector2(hi.x + 2.0, t)]) if horiz else PackedVector2Array([Vector2(t, lo.y - 2.0), Vector2(t, hi.y + 2.0)])
		for piece in Geometry2D.intersect_polyline_with_polygon(seg, poly):
			if piece.size() >= 2:
				lines.append(piece[0])
				lines.append(piece[piece.size() - 1])
		d += course
	if lines.size() >= 2:
		c.draw_multiline(lines, Color(_k(fc, 0.8), 0.6), 2.0)


## A pitched part (gable, hip, burnt): the slopes, then the hips, the valleys and the ridge cap.
static func _pitched(c: CanvasItem, pl: Dictionary, col: Color, course: float) -> void:
	var sl := _slopes(pl.r, bool(pl.x), bool(pl.ha), bool(pl.hb), float(pl.ea), float(pl.eb))
	for f in sl.faces:
		_slope(c, f[0], f[1], col, course)
	var hips: Array = sl.hips
	for k in range(0, hips.size(), 2):
		c.draw_line(hips[k], hips[k + 1], Color(_k(col, 0.5), 0.9), 3.0)
	var vs: Array = sl.valleys
	for k in range(0, vs.size(), 2):
		c.draw_line(vs[k], vs[k + 1], Color(_k(col, 0.42), 0.95), 4.0)
	var rd: Array = sl.ridge
	var ra: Vector2 = rd[0]
	var rb: Vector2 = rd[1]
	if ra.distance_to(rb) > 1.0:
		c.draw_line(ra, rb, Color(_k(col, 0.42), 1.0), 13.0)
		c.draw_line(ra, rb, _k(col, 1.2), 8.0)
		c.draw_line(ra - Vector2(0, 2) if absf(ra.y - rb.y) < 0.5 else ra - Vector2(2, 0), rb - Vector2(0, 2) if absf(ra.y - rb.y) < 0.5 else rb - Vector2(2, 0), _k(col, 1.38), 2.0)
		# the cap's joints
		var marks := PackedVector2Array()
		var dirv := (rb - ra).normalized()
		var nrm := Vector2(-dirv.y, dirv.x) * 4.0
		var t := 18.0
		while t < ra.distance_to(rb) - 6.0:
			var p := ra + dirv * t
			marks.append_array([p - nrm, p + nrm])
			t += 20.0
		if marks.size() >= 2:
			c.draw_multiline(marks, Color(_k(col, 0.7), 0.8), 2.0)


## A lean-to: one slope falling to `dir`, the flashing along its high edge.
static func _lean(c: CanvasItem, r: Rect2, dir: String, col: Color, course: float) -> void:
	_slope(c, _poly_of(r), dir, col, course)
	var hi_a := r.position
	var hi_b := Vector2(r.end.x, r.position.y)
	match dir:
		"n":
			hi_a = Vector2(r.position.x, r.end.y)
			hi_b = r.end
		"e":
			hi_b = Vector2(r.position.x, r.end.y)
		"w":
			hi_a = Vector2(r.end.x, r.position.y)
			hi_b = r.end
	c.draw_line(hi_a, hi_b, Color(0.6, 0.6, 0.58), 6.0)


## A flat deck: the fill, panel seams, a patch or two, a drain (or the saw-tooth's glass rows, a greenhouse's panes, a silo's dome), the parapet on its outer edges (`others`: the plan's
## other rectangles) with the lip's shadow on the deck below its north and west sides.
static func _deck(c: CanvasItem, r: Rect2, deck: Color, trim: Color, others: Array, rng: RandomNumberGenerator, style: String = "flat") -> void:
	c.draw_rect(r, deck)
	var wide := r.size.x >= r.size.y
	var seam := Color(_k(deck, 0.8), 0.6)
	var lit := Color(_k(deck, 1.12), 0.5)
	match style:
		"saw":
			var y := r.position.y + PAR
			while y < r.end.y - PAR - 4.0:
				var band := minf(TILE * 0.5, r.end.y - PAR - y)
				c.draw_rect(Rect2(r.position.x + PAR, y, r.size.x - PAR * 2.0, band), _k(GLASS, 0.85))
				c.draw_line(Vector2(r.position.x + PAR, y + 3.0), Vector2(r.end.x - PAR, y + 3.0), Color(1, 1, 1, 0.3), 2.0)
				var mrect := Rect2(r.position.x + PAR, y + band, r.size.x - PAR * 2.0, minf(TILE, r.end.y - PAR - y - band))
				if mrect.size.y > 0.0:
					c.draw_rect(mrect, _k(deck, 1.1))
					var x := mrect.position.x + 8.0
					var ribs := PackedVector2Array()
					while x < mrect.end.x:
						ribs.append(Vector2(x, mrect.position.y))
						ribs.append(Vector2(x, mrect.end.y))
						x += 10.0
					c.draw_multiline(ribs, seam, 2.0)
				c.draw_line(Vector2(r.position.x + PAR, y + band), Vector2(r.end.x - PAR, y + band), OUTLINE, 2.0)
				y += TILE * 1.5
		"glass":
			c.draw_rect(r.grow(-PAR), Color(GLASS, 0.55))
			var bars := PackedVector2Array()
			var gx := r.position.x + TILE
			while gx < r.end.x - 4.0:
				bars.append_array([Vector2(gx, r.position.y), Vector2(gx, r.end.y)])
				gx += TILE
			var gy := r.position.y + TILE
			while gy < r.end.y - 4.0:
				bars.append_array([Vector2(r.position.x, gy), Vector2(r.end.x, gy)])
				gy += TILE
			if bars.size() >= 2:
				c.draw_multiline(bars, Color(0.82, 0.84, 0.84), 3.0)
		"dome":
			var ctr := r.get_center()
			var rad := minf(r.size.x, r.size.y) * 0.44
			c.draw_circle(ctr + SHADOW_OFF * 0.6, rad, Color(0, 0, 0, 0.25))
			c.draw_circle(ctr, rad, Color(0.6, 0.61, 0.6))
			c.draw_circle(ctr - Vector2(rad, rad) * 0.08, rad * 0.86, Color(0.67, 0.68, 0.67))
			c.draw_circle(ctr - Vector2(rad, rad) * 0.32, rad * 0.3, Color(0.76, 0.77, 0.76))
			c.draw_arc(ctr, rad, 0.0, TAU, 48, OUTLINE, 3.0)
			c.draw_circle(ctr, 10.0, Color(0.4, 0.4, 0.4))
			c.draw_arc(ctr, 10.0, 0.0, TAU, 16, OUTLINE, 2.0)
		_:
			var n_seams := int((r.size.x if wide else r.size.y) / (TILE * 3.0))
			for k in range(1, n_seams + 1):
				var t := float(k) * TILE * 3.0
				if wide:
					c.draw_line(Vector2(r.position.x + t, r.position.y), Vector2(r.position.x + t, r.end.y), seam, 2.0)
					c.draw_line(Vector2(r.position.x + t + 2.0, r.position.y), Vector2(r.position.x + t + 2.0, r.end.y), lit, 1.5)
				else:
					c.draw_line(Vector2(r.position.x, r.position.y + t), Vector2(r.end.x, r.position.y + t), seam, 2.0)
					c.draw_line(Vector2(r.position.x, r.position.y + t + 2.0), Vector2(r.end.x, r.position.y + t + 2.0), lit, 1.5)
			# soft stains, never a hard patch
			for k in 2:
				var rad := rng.randf_range(0.6, 1.2) * TILE
				if r.size.x > rad * 3.0 and r.size.y > rad * 3.0:
					var at := Vector2(rng.randf_range(r.position.x + rad * 1.5, r.end.x - rad * 1.5), rng.randf_range(r.position.y + rad * 1.5, r.end.y - rad * 1.5))
					c.draw_circle(at, rad, Color(0, 0, 0, 0.035))
					c.draw_circle(at + Vector2(rad * 0.25, rad * 0.15), rad * 0.6, Color(0, 0, 0, 0.035))
			if r.size.x > TILE * 2.0 and r.size.y > TILE * 2.0:
				var dp := Vector2(r.end.x - TILE * 0.6, r.end.y - TILE * 0.6)
				c.draw_circle(dp, 15.0, Color(0, 0, 0, 0.1))
				c.draw_circle(dp, 5.0, Color(0.12, 0.12, 0.12))
	# the parapet, on the edges no other part of the building meets
	var sides := {"n": Rect2(r.position, Vector2(r.size.x, PAR)), "s": Rect2(Vector2(r.position.x, r.end.y - PAR), Vector2(r.size.x, PAR)),
		"w": Rect2(r.position, Vector2(PAR, r.size.y)), "e": Rect2(Vector2(r.end.x - PAR, r.position.y), Vector2(PAR, r.size.y))}
	var probe := {"n": Vector2(r.get_center().x, r.position.y - 2.0), "s": Vector2(r.get_center().x, r.end.y + 2.0), "w": Vector2(r.position.x - 2.0, r.get_center().y), "e": Vector2(r.end.x + 2.0, r.get_center().y)}
	for sd in ["n", "w", "s", "e"]:
		var shared := false
		for o in others:
			if (o as Rect2).has_point(probe[sd]):
				shared = true
		if shared:
			continue
		var band: Rect2 = sides[sd]
		if sd == "n":
			c.draw_rect(Rect2(band.position + Vector2(0, PAR), Vector2(band.size.x, 7.0)), Color(0, 0, 0, 0.2))
		elif sd == "w":
			c.draw_rect(Rect2(band.position + Vector2(PAR, 0), Vector2(7.0, band.size.y)), Color(0, 0, 0, 0.2))
		c.draw_rect(band, trim)
		var a: Vector2 = band.position + (Vector2(0, PAR) if sd == "n" else (Vector2(PAR, 0) if sd == "w" else Vector2.ZERO))
		var b: Vector2 = a + (Vector2(band.size.x, 0) if (sd == "n" or sd == "s") else Vector2(0, band.size.y))
		c.draw_line(a, b, Color(_k(trim, 0.6), 0.9), 2.0)


## A chimney at `p` (px): the stack, its shadow, the flue.
static func _chimney(c: CanvasItem, p: Vector2, k: float, brick: Color) -> void:
	var s := TILE * 0.56 * k
	var r := Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s))
	c.draw_rect(Rect2(r.position + SHADOW_OFF * 1.2, r.size), Color(0, 0, 0, 0.28))
	c.draw_rect(r, brick)
	c.draw_rect(Rect2(r.position, Vector2(s, 4.0)), _k(brick, 1.25))
	c.draw_rect(Rect2(r.position, Vector2(4.0, s)), _k(brick, 1.12))
	c.draw_rect(r.grow(-s * 0.26), Color(0.12, 0.1, 0.09))
	c.draw_rect(r, OUTLINE, false, 3.0)


## The roof of a generated house, from its facade (world px).
static func paint_house(c: CanvasItem, h: Dictionary, set) -> void:
	var fac: Dictionary = h.facade
	var id := int(h.id)
	var kit := clampi(int(h.get("roof", id % 3)), 0, 2)
	var burnt := String(fac.get("state", "")) == "burnt"
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 131
	var col: Color = KIT_COL[kit] * RoofLook.tint(kit, int(fac.get("tint_id", 0)))
	col.a = 1.0
	if burnt:
		col = Color(0.24, 0.22, 0.21)
	var styles: Array = fac.get("styles", [])
	var dirs: Array = fac.get("dirs", [])
	var levels: Array = fac.get("levels", [])
	var main_style := String(fac.get("style", "gable"))
	var deck: Color = DECK.get(String(fac.get("flat", "flat_tar")), DECK.flat_tar)
	var trim := _k(deck, 1.4) if deck.get_luminance() < 0.5 else _k(deck, 0.8)
	var pl := plan_of(_parts_of(h), styles, main_style)
	var rects: Array = pl.map(func(q): return q.r)
	var outline := _union(rects)
	for poly in outline:
		var sh := PackedVector2Array()
		for p in poly:
			sh.append(p + SHADOW_OFF)
		c.draw_colored_polygon(sh, SHADOW)
	for k in pl.size():
		var q: Dictionary = pl[k]
		var i := int(q.i)
		var st := _style(styles, i, main_style)
		var pc := col
		if i < levels.size() and int(levels[i]) > 0:
			pc = _k(col, 0.9)
		var others: Array = rects.duplicate()
		others.remove_at(k)
		match st:
			"flat", "saw", "dome", "glass":
				_deck(c, q.r, _k(deck, 0.55) if burnt else deck, trim, others, rng, st)
			"lean":
				_lean(c, q.r, String(dirs[i]) if i < dirs.size() else "s", pc, COURSE[kit])
			_:
				_pitched(c, q, pc, COURSE[kit])
		# a little wear: soft darker patches, never past the edge
		for w in 2:
			var rr: Rect2 = q.r
			var rad := rng.randf_range(0.5, 1.1) * TILE
			if rr.size.x > rad * 2.6 and rr.size.y > rad * 2.6:
				var at := Vector2(rng.randf_range(rr.position.x + rad, rr.end.x - rad), rng.randf_range(rr.position.y + rad, rr.end.y - rad))
				c.draw_circle(at, rad, Color(0.1, 0.08, 0.05, 0.05))
				c.draw_circle(at + Vector2(rad * 0.2, rad * 0.1), rad * 0.6, Color(0.1, 0.08, 0.05, 0.05))
	# holes and tarps
	for hc in fac.get("holes", []):
		var cr := Rect2(Vector2(float(hc.x), float(hc.y)) * TILE, Vector2(TILE, TILE))
		var hole := PackedVector2Array()
		for a in 9:
			hole.append(cr.get_center() + Vector2.from_angle(float(a) / 9.0 * TAU) * TILE * rng.randf_range(0.32, 0.5))
		c.draw_colored_polygon(hole, Color(0.07, 0.06, 0.05))
		c.draw_polyline(_closed(hole), Color(0.3, 0.2, 0.14), 3.0)
		c.draw_line(cr.position + Vector2(8, TILE * 0.3), cr.end - Vector2(10, TILE * 0.4), Color(0.36, 0.25, 0.16), 5.0)
	if not burnt:
		var tcol: Color = TARP.get(String(fac.get("tarp_name", "tarp_blue")), TARP.tarp_blue)
		for tc in fac.get("tarps", []):
			var tr := Rect2(Vector2(float(tc.x), float(tc.y)) * TILE, Vector2(TILE, TILE)).grow(6.0)
			c.draw_rect(Rect2(tr.position + Vector2(4, 5), tr.size), Color(0, 0, 0, 0.22))
			c.draw_rect(tr, tcol)
			c.draw_line(tr.position, tr.end, Color(_k(tcol, 0.75), 0.8), 2.0)
			c.draw_line(Vector2(tr.position.x, tr.get_center().y), Vector2(tr.end.x, tr.get_center().y), Color(_k(tcol, 1.2), 0.8), 2.0)
			c.draw_rect(tr, OUTLINE, false, 2.5)
			for corner in [tr.position, Vector2(tr.end.x, tr.position.y), tr.end, Vector2(tr.position.x, tr.end.y)]:
				c.draw_circle(corner, 4.0, Color(0.85, 0.82, 0.74))
	# the outline, a gutter just inside it
	for poly in outline:
		for ip in Geometry2D.offset_polygon(poly, -5.0, Geometry2D.JOIN_MITER):
			c.draw_polyline(_closed(ip), Color(0, 0, 0, 0.2), 3.0)
		c.draw_polyline(_closed(poly), OUTLINE, 4.0)
	# chimneys (code-drawn: the same light as the slopes), then the kit's things on the roof, the porches and awnings, the sign
	var brick := Color(0.55, 0.3, 0.24) if kit != 0 else Color(0.5, 0.46, 0.42)
	for dc in fac.get("decor", []):
		if String(dc.id).begins_with("chimney"):
			_chimney(c, Vector2(float(dc.x), float(dc.y)) * TILE, float(dc.get("k", 1.0)) * 1.15, brick)
	if set == null or burnt:
		return
	var tex: Texture2D = set.tex
	for dc in fac.get("decor", []):
		var name := String(dc.id)
		if name.begins_with("chimney"):
			continue
		var src := RoofAtlas.extra(set, name)
		if src.size.x <= 0.0:
			continue
		var tl: Vector2 = (set.get("etiles", {}) as Dictionary).get(name, Vector2.ONE)
		var size := tl * TILE * float(dc.get("k", 1.0))
		var at := Vector2(float(dc.x), float(dc.y)) * TILE
		c.draw_texture_rect_region(tex, Rect2(at - size * 0.5, size), src)
	var rx := Vector2(Rect2i(h.rect).position)
	var cm := RoofPaint.Cmds.new()
	for cn in fac.get("canopies", []):
		RoofPaint._canopy(cm, set, Rect2i(h.rect), cn)
	var sg: Dictionary = fac.get("sign", {})
	if not sg.is_empty():
		var ssrc := RoofAtlas.extra(set, "sign_" + String(sg.icon))
		if ssrc.size.x > 0.0:
			var sc := (Vector2(float(sg.x), float(sg.y)) - rx) * TILE
			var ss := Vector2(0.78, 0.78) * TILE
			cm.add(Rect2(sc - ss * 0.5, ss), ssrc, Color.WHITE)
	var off := rx * TILE
	for i in cm.n:
		var k := i * 4
		c.draw_texture_rect_region(tex, Rect2(cm.dst[k] + off.x, cm.dst[k + 1] + off.y, cm.dst[k + 2], cm.dst[k + 3]), Rect2(cm.src[k], cm.src[k + 1], cm.src[k + 2], cm.src[k + 3]), cm.col[i], cm.tr[i] != 0)


## The units each kind of site building carries on its roof (cycled as they are placed): "ac" an air conditioner, "hvac" a big plant box, "vent" a vent cap, "fan" a turbine vent,
## "sky" a skylight, "strip" a long run of skylights, "mast" an aerial mast, "tank" a water tank, "solar" a solar array. A kind not here gets the default.
const UNITS := {
	"hospital": ["hvac", "ac", "vent", "sky", "ac", "tank", "vent"], "clinic": ["ac", "vent", "sky"], "first_aid": ["ac", "vent"],
	"store": ["hvac", "ac", "ac", "vent", "sky", "fan", "ac"], "bakery": ["vent", "ac"], "hardware": ["ac", "vent", "sky"], "kiosk": ["vent"],
	"station": ["mast", "ac", "ac", "vent", "sky", "solar"], "security": ["mast", "ac", "vent"],
	"terminal": ["strip", "hvac", "ac", "vent", "ac", "sky", "fan"], "hangar": ["strip", "fan", "fan", "vent"], "warehouse": ["strip", "fan", "vent", "fan"],
	"depot": ["fan", "vent", "sky"], "workshop": ["fan", "vent", "solar"], "garage": ["vent", "fan"], "motor_pool": ["fan", "vent"], "boiler": ["fan", "vent", "vent"],
	"dock_office": ["ac", "mast", "vent"], "club_shop": ["ac", "vent"], "grounds_store": ["solar", "vent"], "petrol": ["ac", "vent"], "pumps": ["vent"],
}
const UNIT_SIZE := {"ac": Vector2(2.0, 1.4), "hvac": Vector2(3.4, 2.2), "vent": Vector2(0.9, 0.9), "fan": Vector2(1.0, 1.0), "sky": Vector2(2.4, 1.4), "strip": Vector2(6.0, 1.2),
	"mast": Vector2(1.2, 1.2), "tank": Vector2(2.2, 2.2), "solar": Vector2(4.0, 2.0)}


## The painted flat roof of a raid site's building (`roof_look`; world px; drawn once, faded with its roof node). Seeded by the house, so a building always looks the same.
static func paint_look(c: CanvasItem, h: Dictionary) -> void:
	var look: Dictionary = h.roof_look
	var rr: Rect2i = h.rect
	var r := _rect_px(rr)
	var tint: Color = look.get("tint", Color.WHITE)
	var deck := (SITE_LIGHT if int(h.id) % 3 == 0 else SITE_DARK) * tint
	deck.a = 1.0
	var trim: Color = look.get("trim", Color(0.78, 0.77, 0.73))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(h.id) * 7919 + rr.position.x * 131 + rr.position.y
	c.draw_rect(Rect2(r.position + SHADOW_OFF, r.size), SHADOW)
	var inner := r.grow(-PAR * 2.0)
	# the deck (its seams, a patch, a drain) and the parapet, its top catching the light on the north and west
	_deck(c, r, deck, trim, [], rng)
	c.draw_line(r.position + Vector2(2, 2), Vector2(r.end.x - 2.0, r.position.y + 2.0), Color(1, 1, 1, 0.22), 2.0)
	c.draw_line(r.position + Vector2(2, 2), Vector2(r.position.x + 2.0, r.end.y - 2.0), Color(1, 1, 1, 0.22), 2.0)
	# the sign, painted in the middle of a big enough roof
	var sign := String(look.get("sign", ""))
	var side := minf(r.size.x, r.size.y)
	var sign_r := Rect2()
	if sign != "" and side >= TILE * 5.0:
		var s := clampf(side * 0.42, TILE * 2.4, TILE * 9.0)
		if sign == "cross":
			sign_r = Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))
			_paint_cross(c, sign_r)
		else:
			var word := String(look.get("n", "")) if sign == "#" else sign
			var fs := int(clampf(s * (0.8 if sign == "#" else 0.36), 20.0, 150.0))
			var font: Font = ThemeDB.fallback_font
			var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pw := minf(tw + fs * 0.9, inner.size.x - TILE)
			var ph := fs * 1.45
			sign_r = Rect2(r.get_center() - Vector2(pw, ph) * 0.5, Vector2(pw, ph))
			var plate: Color = look.get("plate", Color(0.93, 0.9, 0.82))
			var ink: Color = look.get("ink", Color(0.72, 0.16, 0.14))
			c.draw_rect(sign_r, plate)
			c.draw_rect(sign_r, OUTLINE, false, 4.0)
			c.draw_rect(sign_r.grow(-8.0), Color(ink, 0.6), false, 3.0)
			var base := Vector2(sign_r.get_center().x - tw * 0.5, sign_r.get_center().y + fs * 0.36)
			c.draw_string_outline(font, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, OUTLINE)
			c.draw_string(font, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# the rooftop units, by the building's kind: kept off the sign and off each other, lined up with the roof (a few in a row share one line)
	var kinds: Array = UNITS.get(String(h.get("kind", "")), ["ac", "vent", "sky", "ac", "vent"])
	var area := (r.size.x / TILE) * (r.size.y / TILE)
	var want := clampi(int(area / 30.0), 1, 18)
	var placed: Array = []
	if sign_r.size.x > 0.0:
		placed.append(sign_r.grow(TILE * 0.5))
	var wide := r.size.x >= r.size.y
	var made := 0
	var room := inner.grow(-TILE * 0.3)
	for tries in want * 24:
		if made >= want:
			break
		var kind: String = kinds[(made + tries / 24) % kinds.size()]
		var sz: Vector2 = UNIT_SIZE[kind]
		if kind in ["sky", "strip", "solar"] and not wide:
			sz = Vector2(sz.y, sz.x)
		sz *= TILE
		if room.size.x < sz.x or room.size.y < sz.y:
			continue
		# (snapped to half tiles: the units stand in lines as they do on a real roof)
		var at := Vector2(snappedf(rng.randf_range(room.position.x, room.end.x - sz.x), TILE * 0.5), snappedf(rng.randf_range(room.position.y, room.end.y - sz.y), TILE * 0.5))
		at = at.clamp(room.position, room.end - sz)
		var ur := Rect2(at, sz)
		var clash := false
		for o in placed:
			if (o as Rect2).intersects(ur.grow(TILE * 0.45)):
				clash = true
				break
		if clash:
			continue
		placed.append(ur)
		made += 1
		_paint_unit(c, ur, kind)
	c.draw_rect(r, OUTLINE, false, 4.0)


static func _paint_cross(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.2))
	c.draw_rect(r, Color(0.95, 0.94, 0.9))
	c.draw_rect(r, OUTLINE, false, 4.0)
	var a := r.size.x * 0.22
	var red := Color(0.8, 0.14, 0.13)
	var h := Rect2(r.position.x + r.size.x * 0.14, r.get_center().y - a * 0.5, r.size.x * 0.72, a)
	var v := Rect2(r.get_center().x - a * 0.5, r.position.y + r.size.y * 0.14, a, r.size.y * 0.72)
	var pts := PackedVector2Array([
		Vector2(v.position.x, v.position.y), Vector2(v.end.x, v.position.y), Vector2(v.end.x, h.position.y), Vector2(h.end.x, h.position.y), Vector2(h.end.x, h.end.y),
		Vector2(v.end.x, h.end.y), Vector2(v.end.x, v.end.y), Vector2(v.position.x, v.end.y), Vector2(v.position.x, h.end.y), Vector2(h.position.x, h.end.y),
		Vector2(h.position.x, h.position.y), Vector2(v.position.x, h.position.y), Vector2(v.position.x, v.position.y)])
	c.draw_colored_polygon(pts, red)
	c.draw_polyline(pts, OUTLINE, 4.0)


## A rooftop unit in `r` (px): its shadow to the south east, the body lit on its north and west edges, the outline.
static func _paint_unit(c: CanvasItem, r: Rect2, kind: String) -> void:
	var hi := 1.0 if kind in ["sky", "strip", "solar"] else 1.0 + minf(r.size.x, r.size.y) / TILE * 0.35    # (taller things cast longer shadows)
	if kind in ["fan", "tank", "mast"]:
		var ctr := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		c.draw_circle(ctr + SHADOW_OFF * 0.55 * hi, rad * (0.7 if kind == "mast" else 1.0), Color(0, 0, 0, 0.28))
		match kind:
			"fan":
				c.draw_circle(ctr, rad, Color(0.58, 0.6, 0.6))
				c.draw_circle(ctr, rad * 0.78, Color(0.7, 0.72, 0.72))
				for k in 6:
					var ang := float(k) * TAU / 6.0
					c.draw_line(ctr, ctr + Vector2.from_angle(ang) * rad * 0.76, Color(0.45, 0.47, 0.47), 2.0)
				c.draw_circle(ctr, rad * 0.2, Color(0.38, 0.4, 0.4))
			"tank":
				c.draw_circle(ctr, rad, Color(0.5, 0.56, 0.6))
				c.draw_circle(ctr - Vector2(rad, rad) * 0.1, rad * 0.82, Color(0.6, 0.66, 0.7))
				c.draw_arc(ctr, rad * 0.55, 0.0, TAU, 32, Color(0.42, 0.47, 0.5), 2.0)
				c.draw_circle(ctr - Vector2(rad, rad) * 0.35, rad * 0.16, Color(0.78, 0.82, 0.84))
			_:
				# a lattice mast seen from above: a triangle of legs with its braces, a dish on one face, the red lamp on top
				var tri := PackedVector2Array()
				for k in 3:
					tri.append(ctr + Vector2.from_angle(-PI / 2.0 + float(k) * TAU / 3.0) * rad * 0.8)
				c.draw_colored_polygon(tri, Color(0.42, 0.43, 0.43))
				for k in 3:
					c.draw_line(tri[k], ctr, Color(0.78, 0.78, 0.76), 2.0)
				c.draw_polyline(_closed(tri), Color(0.82, 0.82, 0.8), 3.0)
				c.draw_polyline(_closed(tri), OUTLINE, 1.5)
				var dish := ctr + Vector2(rad * 0.62, rad * 0.25)
				c.draw_circle(dish, rad * 0.32, Color(0.86, 0.86, 0.84))
				c.draw_arc(dish, rad * 0.32, 0.0, TAU, 20, OUTLINE, 2.0)
				c.draw_circle(ctr, 4.0, Color(0.85, 0.2, 0.15))
		if kind != "mast":
			c.draw_arc(ctr, rad, 0.0, TAU, 32, OUTLINE, 3.0)
		return
	c.draw_rect(Rect2(r.position + SHADOW_OFF * 0.55 * hi, r.size), Color(0, 0, 0, 0.28))
	match kind:
		"ac", "hvac":
			c.draw_rect(r, UNIT_GREY)
			c.draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), UNIT_GREY.lightened(0.25))
			c.draw_rect(Rect2(r.position, Vector2(5.0, r.size.y)), UNIT_GREY.lightened(0.15))
			var fr := minf(r.size.y * 0.34, TILE * 0.42)
			var n_fans := 2 if kind == "hvac" else 1
			for f_i in n_fans:
				var f := Vector2(r.position.x + fr * 1.5 + float(f_i) * fr * 2.6, r.get_center().y + 2.0)
				c.draw_circle(f, fr, Color(0.25, 0.26, 0.27))
				for k in 3:
					var ang := float(k) * TAU / 3.0 + 0.4
					c.draw_line(f, f + Vector2.from_angle(ang) * fr * 0.9, UNIT_GREY.darkened(0.2), 4.0)
				c.draw_arc(f, fr, 0, TAU, 20, OUTLINE, 2.0)
			var grille := PackedVector2Array()
			var gx := r.position.x + fr * (1.5 + 2.6 * float(n_fans - 1)) + fr * 1.4
			while gx < r.end.x - 8.0:
				grille.append_array([Vector2(gx, r.position.y + r.size.y * 0.25), Vector2(gx, r.end.y - 8.0)])
				gx += 7.0
			if grille.size() >= 2:
				c.draw_multiline(grille, Color(0, 0, 0, 0.35), 2.0)
		"vent":
			c.draw_rect(r, Color(0.5, 0.52, 0.52))
			c.draw_rect(r.grow(-r.size.x * 0.22), Color(0.2, 0.21, 0.22))
			c.draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(0.68, 0.7, 0.7))
		"solar":
			c.draw_rect(r, Color(0.16, 0.2, 0.32))
			var cell := TILE * 0.5
			var lines := PackedVector2Array()
			var x := r.position.x + cell
			while x < r.end.x - 2.0:
				lines.append_array([Vector2(x, r.position.y), Vector2(x, r.end.y)])
				x += cell
			var y := r.position.y + cell
			while y < r.end.y - 2.0:
				lines.append_array([Vector2(r.position.x, y), Vector2(r.end.x, y)])
				y += cell
			if lines.size() >= 2:
				c.draw_multiline(lines, Color(0.45, 0.55, 0.72), 1.5)
			c.draw_line(r.position + Vector2(6, 6), r.position + Vector2(r.size.x * 0.3, 6), Color(1, 1, 1, 0.4), 3.0)
		_:
			c.draw_rect(r, Color(0.72, 0.74, 0.74))
			var g := r.grow(-7.0)
			c.draw_rect(g, GLASS)
			var along := g.size.x > g.size.y
			var step := TILE * (1.2 if kind == "strip" else 99.0)
			var bars := PackedVector2Array()
			if along:
				var bx := g.position.x + g.size.x * 0.5 if kind != "strip" else g.position.x + step
				while bx < g.end.x - 4.0:
					bars.append_array([Vector2(bx, g.position.y), Vector2(bx, g.end.y)])
					bx += step if kind == "strip" else 1e9
			else:
				var by := g.position.y + g.size.y * 0.5 if kind != "strip" else g.position.y + step
				while by < g.end.y - 4.0:
					bars.append_array([Vector2(g.position.x, by), Vector2(g.end.x, by)])
					by += step if kind == "strip" else 1e9
			if bars.size() >= 2:
				c.draw_multiline(bars, Color(0.72, 0.74, 0.74), 3.0)
			c.draw_line(g.position + Vector2(g.size.x * 0.12, g.size.y * 0.8), g.position + Vector2(g.size.x * 0.32, g.size.y * 0.2), Color(1, 1, 1, 0.35), 4.0)
	c.draw_rect(r, OUTLINE, false, 3.0)
