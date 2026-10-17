## ART PASS (round 11): static ground polish for the prison game only, drawn under the walls and props in 16 x 16 tile chunks (so the camera culls them).
## One light direction everywhere: upper left, so shadows fall to the right and down. Nothing here touches the rules; it reads the world's terrain grid, its objects and (in the base) the Base layout.
## Layers: z 0 ground variety (stains, patches, tyre marks, trampled grass, mud, bones, the yard's drip line, cracks and puddles), z 1 floors per room, door thresholds, room clutter, the walls'
## south faces, wall ambient occlusion, prop contact shadows; z 3 (base only) the walls' concrete coping and the cell doors; z 5 (base only) razor wire and the garden's wire fence.
extends RefCounted

const TILE := 64.0
const CHUNK := 16
const CONCRETE := preload("res://assets/terrain/concrete.png")
const DrawNode := preload("res://scripts/render/draw_node.gd")

const T_CONCRETE := 12
const T_WALL := 20
const T_KITCHEN := 11
## The height of a wall's south face (tiles): a strip of darker brick under every wall whose south side is open, so the walls read as standing up.
const FACE := 0.2
const INK := Color(0.07, 0.06, 0.05)
const STEEL := Color(0.33, 0.35, 0.38)
const STEEL_L := Color(0.62, 0.64, 0.68)
const SAFETY := Color(0.86, 0.68, 0.16, 0.75)
## The look of a ground tile is its kit group (TownArt.GROUNDS index; the prison's own G_ codes are one off from the names, so the look is not the terrain id).
const G_LAWN := 0
const G_ASPHALT := 1
const G_SIDEWALK := 2
const G_PATH := 3

var world
var base    # prison_base.gd instance in the base, null in a raid
var W := 0
var H := 0
var T := PackedByteArray()
var GR := PackedByteArray()
var lanes: Array = []
var seed_i := 1


static func install(w, the_base, seed_v: int) -> void:
	var p := new()
	p.world = w
	p.base = the_base
	p.seed_i = seed_v
	p.W = w.W
	p.H = w.H
	p.T = w.terrain
	p.GR = w.grp
	for m in w.d.marks:
		if String(m.kind) == "lanes":
			p.lanes.append(m)
	w.set_meta("polish", p)    # (the painters are Callables on a RefCounted: keep it alive)
	var low := Node2D.new()
	low.name = "PolishGround"
	low.z_index = 0
	var high := Node2D.new()
	high.name = "PolishFloor"
	high.z_index = 1
	w.add_child(low)
	w.add_child(high)
	var top := Node2D.new()
	top.name = "PolishFence"
	top.z_index = 5
	w.add_child(top)
	var caps := Node2D.new()    # (z 3: over the world's wall tops, which are z 3 too but earlier in the tree; under the tall things and the people)
	caps.name = "PolishWalls"
	caps.z_index = 3
	w.add_child(caps)
	for cy in range(0, p.H, CHUNK):
		for cx in range(0, p.W, CHUNK):
			var a := DrawNode.new()
			a.painter = Callable(p, "_ground").bind(cx, cy)
			low.add_child(a)
			var b := DrawNode.new()
			b.painter = Callable(p, "_floor").bind(cx, cy)
			high.add_child(b)
			if the_base != null:
				var f := DrawNode.new()
				f.painter = Callable(p, "_fence").bind(cx, cy)
				top.add_child(f)
				var wc := DrawNode.new()
				wc.painter = Callable(p, "_walls").bind(cx, cy)
				caps.add_child(wc)


# ------------------------------------------------------------------ helpers --

func _r(x: float, y: float, k: int) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7 + float(k) * 74.7 + float(seed_i) * 0.37) * 43758.5453, 1.0)


func _t(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return T[y * W + x]


func _g(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return GR[y * W + x]


func _wall(x: int, y: int) -> bool:
	return _t(x, y) >= T_WALL


## A soft blob: a few stacked ellipses of falling size, so the edge fades.
func _blob(c: CanvasItem, p: Vector2, rx: float, ry: float, rot: float, col: Color, layers: int = 3) -> void:
	for i in layers:
		var k := 1.0 - float(i) / float(layers) * 0.6
		var pts := PackedVector2Array()
		for j in 12:
			var a := TAU * float(j) / 12.0
			var v := Vector2(cos(a) * rx * k, sin(a) * ry * k).rotated(rot) + p
			pts.append(v)
		c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, col.a / float(layers) * 1.6))


func _in_lane(x: float, y: float) -> bool:
	for m in lanes:
		var hw := float(m.w) / 2.0
		var hh := float(m.h) / 2.0
		if absf(x - float(m.cx)) <= hw and absf(y - float(m.cy)) <= hh:
			if String(m.dir) == "h" and absf(y - float(m.cy)) < 0.5:
				return true
			if String(m.dir) != "h" and absf(x - float(m.cx)) < 0.5:
				return true
	return false


# -------------------------------------------------------------- z 0: ground --

func _ground(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			var t := _g(x, y)
			var fx := float(x)
			var fy := float(y)
			var o := Vector2(_r(fx, fy, 1), _r(fx, fy, 2))
			match t:
				G_ASPHALT:
					if _in_lane(fx + 0.5, fy + 0.5):
						continue
					if _r(fx, fy, 3) < 0.10:    # oil
						_blob(c, Vector2(fx, fy) + o, 0.22 + o.x * 0.2, 0.15 + o.y * 0.15, o.x * 3.0, Color(0.02, 0.02, 0.03, 0.30))
						_blob(c, Vector2(fx, fy) + o + Vector2(-0.03, -0.03), 0.1, 0.07, o.x * 3.0, Color(0.30, 0.34, 0.45, 0.10), 2)
					elif _r(fx, fy, 4) < 0.05:    # a repaired patch
						var pr := Rect2(fx + 0.1 + o.x * 0.2, fy + 0.15 + o.y * 0.2, 0.55 + o.y * 0.2, 0.4 + o.x * 0.2)
						c.draw_rect(pr, Color(0.07, 0.07, 0.09, 0.14))
						c.draw_rect(pr, Color(0.0, 0.0, 0.0, 0.2), false, 0.015)
					elif _r(fx, fy, 5) < 0.025:    # a pothole: dark centre, crumbled rim, a little rain in it
						_blob(c, Vector2(fx, fy) + o, 0.3, 0.22, o.x * 3.0, Color(0.05, 0.05, 0.06, 0.35))
						_blob(c, Vector2(fx, fy) + o + Vector2(0.03, 0.03), 0.17, 0.11, o.x * 3.0, Color(0.0, 0.0, 0.0, 0.55))
						_blob(c, Vector2(fx, fy) + o + Vector2(-0.05, -0.04), 0.07, 0.04, o.x * 3.0, Color(0.5, 0.58, 0.7, 0.22), 2)
				G_SIDEWALK:
					if _r(fx, fy, 6) < 0.22:    # damp or stained slab: breaks the repeat of the texture
						_blob(c, Vector2(fx, fy) + o, 0.35 + o.x * 0.4, 0.3 + o.y * 0.3, o.y * 3.0, Color(0.10, 0.09, 0.08, 0.10 + o.x * 0.08))
					if _r(fx, fy, 7) < 0.05:
						_blob(c, Vector2(fx, fy) + o, 0.12, 0.09, o.x * 3.0, Color(0.03, 0.02, 0.02, 0.32))    # oil
					if _r(fx, fy, 8) < 0.04:    # a lighter, swept slab
						c.draw_rect(Rect2(fx, fy, 1, 1), Color(1, 1, 1, 0.045))
				G_PATH:
					if _r(fx, fy, 9) < 0.28:
						_blob(c, Vector2(fx, fy) + o, 0.3 + o.x * 0.3, 0.2 + o.y * 0.2, o.y * 3.0, Color(0.12, 0.08, 0.04, 0.16))
					if _r(fx, fy, 10) < 0.18:
						_blob(c, Vector2(fx, fy) + o, 0.25, 0.16, o.y * 3.0, Color(0.78, 0.68, 0.5, 0.07))
					if _r(fx, fy, 11) < 0.10:    # pebbles
						for k in 3:
							var q := Vector2(_r(fx, fy, 20 + k), _r(fx, fy, 30 + k))
							c.draw_circle(Vector2(fx, fy) + q, 0.03 + q.x * 0.02, Color(0.18, 0.15, 0.12, 0.55))
				G_LAWN:
					if _r(fx, fy, 12) < 0.07:
						_blob(c, Vector2(fx, fy) + o, 0.5 + o.x * 0.4, 0.35 + o.y * 0.3, o.y * 3.0, Color(0.06, 0.12, 0.04, 0.16))
					for k in 2:    # tufts: three short strokes
						if _r(fx, fy, 40 + k) < 0.55:
							var q := Vector2(_r(fx, fy, 50 + k), _r(fx, fy, 60 + k))
							var col := Color(0.10, 0.22, 0.08, 0.55) if _r(fx, fy, 70 + k) < 0.5 else Color(0.5, 0.58, 0.25, 0.45)
							var b := Vector2(fx, fy) + q
							c.draw_line(b, b + Vector2(-0.05, -0.12), col, 0.025)
							c.draw_line(b, b + Vector2(0.0, -0.15), col, 0.025)
							c.draw_line(b, b + Vector2(0.06, -0.11), col, 0.025)
	for m in lanes:
		_tyres(c, m, cx, cy)
	if base != null:
		_outside(c, cx, cy)
		_yard_marks(c, cx, cy)
		_yard_ground(c, cx, cy)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tyres(c: CanvasItem, m: Dictionary, cx: int, cy: int) -> void:
	var horiz := String(m.dir) == "h"
	var len_t := float(m.w) if horiz else float(m.h)
	var wid_t := float(m.h) if horiz else float(m.w)
	var c0 := (float(m.cx) if horiz else float(m.cy)) - len_t / 2.0
	var cc := float(m.cy) if horiz else float(m.cx)
	var n := int(len_t / 3.0)
	for i in n:
		var a := c0 + _r(float(i), cc, 80) * len_t
		var seg := 2.0 + _r(float(i), cc, 81) * 5.0
		var off := (_r(float(i), cc, 82) - 0.5) * (wid_t - 1.6)
		if absf(off) < 0.5:
			off += 0.9 if off >= 0.0 else -0.9
		for k in 2:
			var d := off + (-0.28 if k == 0 else 0.28)
			var p0 := Vector2(a, cc + d) if horiz else Vector2(cc + d, a)
			var p1 := Vector2(a + seg, cc + d) if horiz else Vector2(cc + d, a + seg)
			var mid := (p0 + p1) / 2.0
			if int(mid.x) < cx or int(mid.x) >= cx + CHUNK or int(mid.y) < cy or int(mid.y) >= cy + CHUNK:
				continue
			c.draw_line(p0, p1, Color(0.0, 0.0, 0.0, 0.14), 0.06)


## The base only: the dead press on the fence south of the gate, and trample the grass to bare mud; bones and rags in it.
func _outside(c: CanvasItem, cx: int, cy: int) -> void:
	var gx: float = base.GATE_POS.x
	var fy: float = float(base.FENCE.end.y)
	for i in 70:
		var x := gx + (_r(float(i), 1.0, 90) + _r(float(i), 2.0, 91) - 1.0) * 20.0
		var y := fy + 0.2 + _r(float(i), 3.0, 92) * 3.2
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK:
			continue
		if _g(int(x), int(y)) != G_LAWN:
			continue
		var f := 1.0 - minf(absf(x - gx) / 20.0, 1.0)
		_blob(c, Vector2(x, y), 0.8 + _r(float(i), 4.0, 93), 0.4 + _r(float(i), 5.0, 94) * 0.4, 0.0, Color(0.20, 0.14, 0.08, 0.20 * f + 0.04))
	for i in 18:    # mud with a wet shine
		var x := gx + (_r(float(i), 6.0, 95) - 0.5) * 24.0
		var y := fy + 0.4 + _r(float(i), 7.0, 96) * 2.6
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK or _g(int(x), int(y)) != G_LAWN:
			continue
		_blob(c, Vector2(x, y), 0.5 + _r(float(i), 8.0, 97) * 0.4, 0.28, _r(float(i), 9.0, 98) * 0.6, Color(0.13, 0.09, 0.05, 0.38))
		_blob(c, Vector2(x - 0.1, y - 0.07), 0.2, 0.09, 0.0, Color(0.6, 0.62, 0.6, 0.14), 2)
	for i in 26:    # bones and rags
		var x := gx + (_r(float(i), 10.0, 99) - 0.5) * 28.0
		var y := fy + 0.3 + _r(float(i), 11.0, 100) * 3.4
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK or _g(int(x), int(y)) != G_LAWN:
			continue
		var a := _r(float(i), 12.0, 101) * TAU
		var d := Vector2(cos(a), sin(a)) * (0.07 + _r(float(i), 13.0, 102) * 0.08)
		if i % 5 == 0:
			c.draw_circle(Vector2(x, y), 0.07, Color(0.82, 0.8, 0.7, 0.9))    # a skull
			c.draw_circle(Vector2(x - 0.025, y), 0.016, Color(0.1, 0.08, 0.06))
			c.draw_circle(Vector2(x + 0.025, y), 0.016, Color(0.1, 0.08, 0.06))
		elif i % 3 == 0:
			var cols := [Color(0.35, 0.18, 0.15, 0.8), Color(0.25, 0.3, 0.35, 0.8), Color(0.4, 0.38, 0.3, 0.8)]
			c.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 0.22, y + 0.05), Vector2(x + 0.15, y + 0.2), Vector2(x - 0.05, y + 0.14)]), cols[i % 3])
		else:
			c.draw_line(Vector2(x, y) - d, Vector2(x, y) + d, Color(0.0, 0.0, 0.0, 0.3), 0.07)
			c.draw_line(Vector2(x, y) - d + Vector2(-0.01, -0.01), Vector2(x, y) + d + Vector2(-0.01, -0.01), Color(0.86, 0.84, 0.74, 0.95), 0.05)
	# paths worn by the guards inside: bare strips along the fence
	for i in 26:
		var x: float = float(base.FENCE.position.x) + 2.0 + float(i) * 3.4
		var y: float = float(base.FENCE.end.y) - 2.2 + (_r(float(i), 14.0, 103) - 0.5) * 0.5
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK:
			continue
		_blob(c, Vector2(x, y), 1.5, 0.35, 0.0, Color(0.1, 0.07, 0.04, 0.16))


## The yard inside the fence: a strip of gravel where every wall meets the slabs (the drip line), cracks with weeds in them, a few puddles.
func _yard_ground(c: CanvasItem, cx: int, cy: int) -> void:
	var fr := Rect2i(base.FENCE).grow(-1)
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if not fr.has_point(Vector2i(x, y)) or _wall(x, y):
				continue
			var g := _g(x, y)
			if g != G_SIDEWALK and g != G_ASPHALT:
				continue
			var fx := float(x)
			var fy := float(y)
			if g == G_SIDEWALK:
				for side in 4:
					var nb := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)][side] as Vector2i
					if not _brick(x + nb.x, y + nb.y):
						continue
					var deep := 0.42 if side == 0 else 0.3    # (a wall to the north stands its face over the first 0.2)
					var r: Rect2 = [Rect2(fx, fy, 1.0, deep), Rect2(fx, fy + 1.0 - deep, 1.0, deep), Rect2(fx, fy, deep, 1.0), Rect2(fx + 1.0 - deep, fy, deep, 1.0)][side]
					c.draw_rect(r, Color(0.36, 0.34, 0.31, 0.85))
					for k in 9:
						var q := r.position + Vector2(_r(fx, fy, 330 + k + side * 10) * r.size.x, _r(fx, fy, 340 + k + side * 10) * r.size.y)
						c.draw_circle(q, 0.025 + _r(fx, fy, 350 + k) * 0.02, Color(0.55, 0.52, 0.47) if k % 2 == 0 else Color(0.22, 0.21, 0.2))
					var e0: Vector2 = [r.position + Vector2(0, deep), r.position, r.position + Vector2(deep, 0), r.position][side]
					c.draw_line(e0, e0 + (Vector2(1, 0) if side < 2 else Vector2(0, 1)), Color(0.52, 0.5, 0.46), 0.03)    # the kerb of the strip
			var rc := _r(fx, fy, 360)
			if rc < 0.07:    # a crack, and weeds in it
				var p0 := Vector2(fx, fy) + Vector2(_r(fx, fy, 361), _r(fx, fy, 362)) * 0.6 + Vector2(0.2, 0.2)
				var pts := PackedVector2Array([p0])
				var dir := Vector2.RIGHT.rotated(_r(fx, fy, 363) * TAU)
				for k in 4:
					dir = dir.rotated((_r(fx, fy, 364 + k) - 0.5) * 1.4)
					pts.append(pts[pts.size() - 1] + dir * 0.17)
				c.draw_polyline(pts, Color(0.06, 0.05, 0.04, 0.55), 0.025)
				for k in 2:
					var b := pts[1 + k * 2]
					var col := Color(0.24, 0.36, 0.14, 0.9)
					c.draw_line(b, b + Vector2(-0.06, -0.1), col, 0.025)
					c.draw_line(b, b + Vector2(0.0, -0.13), col, 0.025)
					c.draw_line(b, b + Vector2(0.06, -0.09), col, 0.025)
			elif rc > 0.988:    # a shallow puddle with the sky in it
				var pp := Vector2(fx, fy) + Vector2(0.5, 0.5)
				_blob(c, pp, 0.45, 0.28, _r(fx, fy, 370) * 3.0, Color(0.12, 0.13, 0.14, 0.35))
				_blob(c, pp + Vector2(-0.06, -0.05), 0.3, 0.16, _r(fx, fy, 370) * 3.0, Color(0.55, 0.62, 0.7, 0.18), 2)


## Tyre ruts and oil where the truck stands, a scorch ring at each fire.
func _yard_marks(c: CanvasItem, cx: int, cy: int) -> void:
	var tp: Vector2 = base.stations["truck"]
	for k in 2:
		var y := tp.y + (-0.7 if k == 0 else 0.7)
		var x0 := tp.x - 3.0
		if int(tp.x) < cx or int(tp.x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK:
			continue
		c.draw_line(Vector2(x0, y), Vector2(tp.x + 3.0, y), Color(0, 0, 0, 0.18), 0.1)
	for f in base.fires:
		var fv: Vector2 = f
		if int(fv.x) < cx or int(fv.x) >= cx + CHUNK or int(fv.y) < cy or int(fv.y) >= cy + CHUNK:
			continue
		_blob(c, fv, 1.1, 0.95, 0.0, Color(0.03, 0.02, 0.02, 0.42))
		for j in 8:
			var a := TAU * float(j) / 8.0 + 0.3
			c.draw_circle(fv + Vector2(cos(a), sin(a)) * 0.62, 0.07, Color(0.28, 0.27, 0.26, 0.9))    # fire ring stones


# -------------------------------------------------------------- z 1: floors --

func _floor(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	if base != null:
		_rooms(c, cx, cy)
		_thresholds(c, cx, cy)
		_dress(c, cx, cy)
		_faces(c, cx, cy)
	_ao(c, cx, cy)
	_shadows(c, cx, cy)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _floor_tile(c: CanvasItem, x: int, y: int, kind: String) -> void:
	var fx := float(x)
	var fy := float(y)
	var o := Vector2(_r(fx, fy, 110), _r(fx, fy, 111))
	match kind:
		"cell", "work", "store":
			var src := Rect2(o.x * 384.0, o.y * 384.0, 128.0, 128.0)
			var v := 0.82 + _r(fx, fy, 112) * 0.2
			var tint := Color(v, v, v * 1.02) if kind == "cell" else Color(v * 0.95, v * 0.95, v * 0.92)
			c.draw_texture_rect_region(CONCRETE, Rect2(fx, fy, 1, 1), src, tint)
			c.draw_rect(Rect2(fx, fy + 0.96, 1, 0.04), Color(0, 0, 0, 0.35))    # slab joints
			c.draw_rect(Rect2(fx + 0.96, fy, 0.04, 1), Color(0, 0, 0, 0.30))
			c.draw_rect(Rect2(fx, fy, 1, 0.025), Color(1, 1, 1, 0.07))
			if _r(fx, fy, 113) < 0.3:
				_blob(c, Vector2(fx, fy) + o, 0.3 + o.x * 0.3, 0.25, o.y * 3.0, Color(0.08, 0.08, 0.07, 0.14))
			if kind == "work" and _r(fx, fy, 114) < 0.12:
				_blob(c, Vector2(fx, fy) + o, 0.15 + o.y * 0.3, 0.1 + o.x * 0.16, o.x * 6.0, Color(0.02, 0.02, 0.02, 0.34))    # oil
				_blob(c, Vector2(fx, fy) + o + Vector2(-0.04, -0.03), 0.1, 0.06, o.x * 3.0, Color(0.4, 0.4, 0.55, 0.12), 2)
		"tile", "lino", "ktile":
			# canteen: worn cream and sage; infirmary: pale green lino, low contrast; kitchen: red quarry tiles
			var a := Color(0.76, 0.73, 0.63) if kind == "tile" else (Color(0.77, 0.83, 0.80) if kind == "lino" else Color(0.55, 0.37, 0.29))
			var b := Color(0.67, 0.68, 0.61) if kind == "tile" else (Color(0.71, 0.78, 0.76) if kind == "lino" else Color(0.49, 0.33, 0.26))
			if kind == "lino":    # sheet lino: one calm square a tile, a faint seam, a slight shift of tone
				var col := a if (x + y) % 2 == 0 else b
				var v := 0.95 + _r(fx, fy, 115) * 0.07
				c.draw_rect(Rect2(fx, fy, 1, 1), Color(col.r * v, col.g * v, col.b * v))
				c.draw_rect(Rect2(fx, fy, 1, 0.02), Color(1, 1, 1, 0.12))
			else:
				for j in 4:
					var q := Vector2(float(j % 2), float(j / 2)) * 0.5
					var col := a if (j + x + y) % 2 == 0 else b
					var v := 0.92 + _r(fx + q.x, fy + q.y, 115) * 0.1
					c.draw_rect(Rect2(fx + q.x, fy + q.y, 0.5, 0.5), Color(col.r * v, col.g * v, col.b * v))
				c.draw_rect(Rect2(fx, fy + 0.49, 1, 0.02), Color(0.2, 0.2, 0.18, 0.35))    # grout
				c.draw_rect(Rect2(fx + 0.49, fy, 0.02, 1), Color(0.2, 0.2, 0.18, 0.35))
			c.draw_rect(Rect2(fx, fy + 0.97, 1, 0.03), Color(0.1, 0.1, 0.08, 0.30))
			if _r(fx, fy, 116) < 0.22:
				_blob(c, Vector2(fx, fy) + o, 0.3, 0.22, o.y * 3.0, Color(0.15, 0.12, 0.08, 0.16))    # scuffs and grime


func _room_kind(x: int, y: int) -> String:
	if _wall(x, y) or _t(x, y) != T_CONCRETE and _t(x, y) != 7 and _t(x, y) != T_KITCHEN:
		return ""
	for z in base.ZONES:
		var r: Rect2i = z.rect
		if not r.has_point(Vector2i(x, y)):
			continue
		match String(z.id):
			"cells":
				return "cell"
			"canteen":
				return "ktile" if y < 12 else "tile"
			"infirmary":
				return "lino"
			"workshop":
				return "store" if base.STORES.has_point(Vector2i(x, y)) else "work"
	return ""


func _rooms(c: CanvasItem, cx: int, cy: int) -> void:
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			var k := _room_kind(x, y)
			if k != "":
				_floor_tile(c, x, y, k)
	# drains in the cells and the corridor
	for z in base.ZONES:
		var id := String(z.id)
		if id != "cells":
			continue
		var r: Rect2i = z.rect
		for row in 2:
			for i in 6:
				var gx := float(r.position.x + 1 + i * 4) + 1.5
				var gy := float(r.position.y + (3 if row == 0 else 11)) + 0.55
				if int(gx) < cx or int(gx) >= cx + CHUNK or int(gy) < cy or int(gy) >= cy + CHUNK:
					continue
				_drain(c, Vector2(gx, gy))
		for i in 4:    # corridor gutter drains
			var gx := float(r.position.x + 3 + i * 6)
			var gy := float(r.position.y + 7) + 0.5
			if int(gx) >= cx and int(gx) < cx + CHUNK and int(gy) >= cy and int(gy) < cy + CHUNK:
				_drain(c, Vector2(gx, gy))


func _drain(c: CanvasItem, p: Vector2) -> void:
	_blob(c, p, 0.36, 0.3, 0.0, Color(0.0, 0.0, 0.0, 0.25))
	c.draw_circle(p, 0.15, Color(0.11, 0.11, 0.12))
	c.draw_arc(p, 0.15, 0.0, TAU, 14, Color(0.4, 0.4, 0.42), 0.025)
	for k in 5:
		var xx := -0.1 + float(k) * 0.05
		c.draw_line(p + Vector2(xx, -0.1), p + Vector2(xx, 0.1), Color(0.34, 0.34, 0.36), 0.018)


## Ambient occlusion where a wall meets the ground. Light comes from the upper left: a long soft shadow to the right and down, a thin dark seam on the lit sides.
func _ao(c: CanvasItem, cx: int, cy: int) -> void:
	var dark := Color(0.02, 0.015, 0.01, 0.34)
	var none := Color(0.02, 0.015, 0.01, 0.0)
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if not _wall(x, y):
				continue
			var fx := float(x)
			var fy := float(y)
			if _t(x + 1, y) >= 0 and not _wall(x + 1, y) and _t(x + 1, y) != 0:
				_grad(c, Vector2(fx + 1.0, fy), Vector2(0.55, 1.0), true, dark, none)
			if _t(x, y + 1) >= 0 and not _wall(x, y + 1) and _t(x, y + 1) != 0:
				var f := FACE if base != null else 0.0    # (in the base the wall's south face stands there first: the shadow starts at its foot)
				_grad(c, Vector2(fx, fy + 1.0 + f), Vector2(1.0, 0.6), false, dark, none)
			if _t(x - 1, y) >= 0 and not _wall(x - 1, y):
				_grad(c, Vector2(fx - 0.2, fy), Vector2(0.2, 1.0), true, none, Color(dark.r, dark.g, dark.b, 0.2))
			if _t(x, y - 1) >= 0 and not _wall(x, y - 1):
				_grad(c, Vector2(fx, fy - 0.22), Vector2(1.0, 0.22), false, none, Color(dark.r, dark.g, dark.b, 0.2))


## A quad with a colour ramp: `horiz` ramps along x (from `a` at the left edge to `b` at the right), else along y.
func _grad(c: CanvasItem, p: Vector2, s: Vector2, horiz: bool, a: Color, b: Color) -> void:
	var pts := PackedVector2Array([p, p + Vector2(s.x, 0), p + s, p + Vector2(0, s.y)])
	var cols := PackedColorArray([a, b, b, a]) if horiz else PackedColorArray([a, a, b, b])
	c.draw_polygon(pts, cols)


## Contact shadows under every solid prop (the sprites carry only a dark outline).
func _shadows(c: CanvasItem, cx: int, cy: int) -> void:
	for o in world.d.objects:
		if not bool(o.get("solid", false)):
			continue
		var kind := String(o.kind)
		if kind.contains("fence") or kind.contains("wall") or kind.contains("lamp") or kind.contains("walkway") or kind.contains("tower") or kind.contains("ladder") or kind == "campfire" or kind.begins_with("car") or kind.contains("truck") or kind.contains("van") or kind.contains("bus") or float(o.w) * float(o.h) > 12.0:
			continue
		var w := float(o.w)
		var h := float(o.h)
		var f := String(o.get("facing", "s"))
		if f == "e" or f == "w":
			var tmp := w
			w = h
			h = tmp
		var ox := float(o.cx)
		var oy := float(o.cy)
		if int(ox) < cx - 1 or int(ox) >= cx + CHUNK + 1 or int(oy) < cy - 1 or int(oy) >= cy + CHUNK + 1:
			continue
		for i in 3:
			var g := 0.05 + float(i) * 0.035
			var r := Rect2(ox - w / 2.0 + 0.1 + g * 0.5, oy - h / 2.0 + 0.14 + g * 0.5, w + g, h + g)
			c.draw_rect(r, Color(0.02, 0.015, 0.01, 0.11))


func _in(cx: int, cy: int, p: Vector2) -> bool:
	return int(p.x) >= cx and int(p.x) < cx + CHUNK and int(p.y) >= cy and int(p.y) < cy + CHUNK


## A brick or plaster wall (not the metal of a fence, which is a wall to the rules too).
func _brick(x: int, y: int) -> bool:
	var t := _t(x, y)
	return t == T_WALL or t == T_WALL + 1


## A flat shape with the house ink round it and a soft drop shadow to the lower right (the one light of the game is at the upper left).
func _box(c: CanvasItem, r: Rect2, col: Color, shadow: bool = true, ink_w: float = 0.03) -> void:
	if shadow:
		c.draw_rect(Rect2(r.position + Vector2(0.05, 0.07), r.size), Color(0.02, 0.015, 0.01, 0.22))
	c.draw_rect(r, col)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, minf(0.04, r.size.y * 0.3))), Color(1, 1, 1, 0.14))
	c.draw_rect(r, INK, false, ink_w)


## Yellow and black hazard stripes in a rect (tiles), the stripes leaning 45 degrees.
func _hazard(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r, Color(0.86, 0.68, 0.16, 0.8))
	var horiz := r.size.x >= r.size.y
	var n := int((r.size.x if horiz else r.size.y) / 0.2)
	var t := r.size.y if horiz else r.size.x
	for i in n:
		if i % 2 == 1:
			continue
		var s := float(i) * 0.2
		var pts := PackedVector2Array()
		if horiz:
			pts = PackedVector2Array([r.position + Vector2(s, t), r.position + Vector2(s + t, 0), r.position + Vector2(minf(s + t + 0.2, r.size.x), 0), r.position + Vector2(minf(s + 0.2, r.size.x), t)])
		else:
			pts = PackedVector2Array([r.position + Vector2(0, s + t), r.position + Vector2(t, s), r.position + Vector2(t, minf(s + 0.2, r.size.y)), r.position + Vector2(0, minf(s + t + 0.2, r.size.y))])
		c.draw_colored_polygon(pts, Color(0.08, 0.08, 0.07, 0.8))
	c.draw_rect(r, Color(0, 0, 0, 0.35), false, 0.02)


## The south face of every brick wall over open ground: darker brick in courses, a lit seam at the top, a dark foot.
func _faces(c: CanvasItem, cx: int, cy: int) -> void:
	var face := Color(0.42, 0.21, 0.16)
	var mortar := Color(0.27, 0.15, 0.12)
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if not _brick(x, y) or _wall(x, y + 1) or _t(x, y + 1) <= 0:
				continue
			var fx := float(x)
			var fy := float(y) + 1.0
			var v := 0.94 + _r(fx, fy, 300) * 0.1
			c.draw_rect(Rect2(fx, fy, 1.0, FACE), Color(face.r * v, face.g * v, face.b * v))
			c.draw_rect(Rect2(fx, fy + FACE * 0.5 - 0.008, 1.0, 0.016), mortar)
			for k in 4:    # the head joints, every other course offset by half a brick
				c.draw_rect(Rect2(fx + 0.125 + float(k) * 0.25, fy, 0.014, FACE * 0.5), mortar)
				c.draw_rect(Rect2(fx + float(k) * 0.25, fy + FACE * 0.5, 0.014, FACE * 0.5), mortar)
			c.draw_rect(Rect2(fx, fy + FACE - 0.03, 1.0, 0.03), INK)
			c.draw_rect(Rect2(fx, fy, 1.0, 0.025), Color(0.0, 0.0, 0.0, 0.35))
			if not _brick(x - 1, y) or _wall(x - 1, y + 1):    # the face ends: a dark end edge
				c.draw_rect(Rect2(fx, fy, 0.025, FACE), INK)
			if not _brick(x + 1, y) or _wall(x + 1, y + 1):
				c.draw_rect(Rect2(fx + 0.975, fy, 0.025, FACE), INK)


## Doorways: a steel threshold plate across the opening and a fan of grime on both sides, where every boot goes.
func _thresholds(c: CanvasItem, cx: int, cy: int) -> void:
	var list: Array = []
	for d in base.doors():
		list.append(Rect2(d.rect))
	for z in base.ZONES:    # the cell doors
		if String(z.id) != "cells":
			continue
		var r: Rect2i = z.rect
		for row in 2:
			for i in 6:
				list.append(Rect2(float(r.position.x + 2 + i * 4), float(r.position.y + (5 if row == 0 else 9)), 1, 1))
	for r in list:
		var rr: Rect2 = r
		var m := rr.get_center()
		if not _in(cx, cy, m):
			continue
		var horiz := rr.size.x >= rr.size.y
		var along := Vector2(1, 0) if horiz else Vector2(0, 1)
		var out := Vector2(0, 1) if horiz else Vector2(1, 0)
		var span: float = rr.size.x if horiz else rr.size.y
		for s in [-1.0, 1.0]:
			_blob(c, m + out * s * 0.85, (span * 0.5 + 0.2) if horiz else 0.45, 0.45 if horiz else (span * 0.5 + 0.2), 0.0, Color(0.10, 0.08, 0.05, 0.16))
			_blob(c, m + out * s * 0.6 + along * (_r(m.x, m.y, 301) - 0.5) * span * 0.5, 0.25, 0.2, 0.0, Color(0.08, 0.06, 0.04, 0.18), 2)
		var plate := Rect2(rr.position + (Vector2(0, 0.42) if horiz else Vector2(0.42, 0)), Vector2(rr.size.x, 0.16) if horiz else Vector2(0.16, rr.size.y))
		c.draw_rect(plate, Color(0.5, 0.51, 0.52))
		c.draw_rect(plate, INK, false, 0.025)
		var n := int(span / 0.14)
		for k in n:    # the tread of the plate
			var p := plate.position + along * (0.07 + float(k) * 0.14) + out * 0.08
			c.draw_line(p - out * 0.045 - along * 0.03, p + out * 0.045 + along * 0.03, Color(0.7, 0.72, 0.74, 0.8), 0.018)


## Small things that say what each room is for (drawn on the floor, under the props and the people; nothing here is solid).
func _dress(c: CanvasItem, cx: int, cy: int) -> void:
	_dress_cells(c, cx, cy)
	_dress_canteen(c, cx, cy)
	_dress_infirmary(c, cx, cy)
	_dress_workshop(c, cx, cy)
	_dress_stores(c, cx, cy)


func _dress_cells(c: CanvasItem, cx: int, cy: int) -> void:
	var r: Rect2i = base.CELLS
	var x0 := float(r.position.x)
	var y0 := float(r.position.y)
	# the corridor: a yellow line along both rows of cell fronts, broken at each door
	for row in 2:
		var ly := y0 + (6.3 if row == 0 else 8.84)    # (the north line clear of the wall's face)
		for x in range(int(x0) + 1, int(x0) + 25):
			if (x - int(x0) - 2) % 4 == 0 or not _in(cx, cy, Vector2(float(x) + 0.5, ly)):
				continue
			c.draw_rect(Rect2(float(x), ly, 1.0, 0.06), SAFETY)
	# each cell: a few belongings, never the same twice
	for row in 2:
		for i in 6:
			var ix := x0 + 1.0 + float(i) * 4.0
			var iy := y0 + (1.0 if row == 0 else 10.0)
			var mid := Vector2(ix + 1.6, iy + 2.0)
			if not _in(cx, cy, mid):
				continue
			var k := float(i * 2 + row)
			var cols := [Color(0.5, 0.3, 0.26), Color(0.33, 0.39, 0.48), Color(0.42, 0.44, 0.32), Color(0.56, 0.5, 0.38), Color(0.4, 0.35, 0.4)]
			if _r(k, 1.0, 310) < 0.75:    # a rug or a blanket on the floor
				var rug := Rect2(ix + 1.12, iy + (1.2 if row == 0 else 1.0), 0.72, 0.95)
				_box(c, rug, cols[int(_r(k, 2.0, 311) * 5.0) % 5], true, 0.025)
				for s in 3:
					c.draw_line(rug.position + Vector2(0.06, 0.2 + float(s) * 0.25), rug.position + Vector2(0.66, 0.2 + float(s) * 0.25), Color(1, 1, 1, 0.12), 0.02)
			var corner := Vector2(ix + 2.55, iy + (0.35 if row == 0 else 3.45))
			if _r(k, 3.0, 312) < 0.6:    # a stack of books against the wall
				for s in 3:
					var bc: Color = cols[(i + s + row) % 5].lightened(0.1)
					_box(c, Rect2(corner + Vector2(-0.22 + float(s) * 0.02, -0.1 + float(s) * 0.03 - float(s) * 0.07), Vector2(0.34, 0.12)), bc, s == 0, 0.02)
			else:    # papers and a letter
				for s in 3:
					var pp := corner + Vector2(-0.3 + float(s) * 0.12, -0.08 + _r(k, float(s), 313) * 0.1)
					_box(c, Rect2(pp, Vector2(0.2, 0.26)), Color(0.9, 0.88, 0.8), s == 0, 0.015)
			if _r(k, 4.0, 314) < 0.55:    # a tin cup
				var cp := Vector2(ix + 1.25, iy + (0.45 if row == 0 else 3.5))
				c.draw_circle(cp + Vector2(0.03, 0.04), 0.08, Color(0, 0, 0, 0.25))
				c.draw_circle(cp, 0.08, INK)
				c.draw_circle(cp, 0.06, Color(0.6, 0.62, 0.64))
				c.draw_circle(cp, 0.035, Color(0.25, 0.2, 0.15))
			if _r(k, 5.0, 315) < 0.5:    # the days counted on the wall's foot
				var tp := Vector2(ix + 0.15, iy + (3.7 if row == 0 else 0.15))
				for s in 4:
					c.draw_line(tp + Vector2(float(s) * 0.07, 0), tp + Vector2(float(s) * 0.07, 0.16), Color(0.92, 0.9, 0.82, 0.7), 0.018)
				c.draw_line(tp + Vector2(-0.03, 0.12), tp + Vector2(0.25, 0.03), Color(0.92, 0.9, 0.82, 0.7), 0.018)


func _dress_canteen(c: CanvasItem, cx: int, cy: int) -> void:
	# benches along both long sides of every table
	for rr in 2:
		for cc in 3:
			var t := Vector2(41.0 + float(cc) * 5.0, 14.5 + float(rr) * 3.0)
			if not _in(cx, cy, t):
				continue
			for s in [-1.0, 1.0]:
				var b := Rect2(t.x - 0.85, t.y + s * 0.62 - 0.11, 1.7, 0.22)
				_box(c, b, Color(0.52, 0.36, 0.22), true, 0.025)
				c.draw_line(b.position + Vector2(0.05, 0.11), b.position + Vector2(1.65, 0.11), Color(0.36, 0.24, 0.14), 0.015)
	# the kitchen: rubber mats where the cooks stand, a floor drain
	for m in [Rect2(38.1, 8.08, 4.8, 0.55), Rect2(48.1, 8.08, 2.0, 0.55), Rect2(54.1, 8.08, 1.0, 0.55)]:
		var mr: Rect2 = m
		if not _in(cx, cy, mr.position + Vector2(0.1, 0.1)):
			continue
		c.draw_rect(mr, Color(0.13, 0.13, 0.14))
		c.draw_rect(mr, INK, false, 0.025)
		var n := int(mr.size.x / 0.16)
		for k in n:
			for j in 3:
				c.draw_circle(mr.position + Vector2(0.1 + float(k) * 0.16, 0.12 + float(j) * 0.16), 0.03, Color(0.24, 0.24, 0.26))
	var d := Vector2(46.5, 9.5)
	if _in(cx, cy, d):
		_drain(c, d)
	var g := Vector2(49.0, 8.8)    # grease by the stoves
	if _in(cx, cy, g):
		_blob(c, g, 0.6, 0.3, 0.0, Color(0.15, 0.1, 0.03, 0.22))


func _dress_infirmary(c: CanvasItem, cx: int, cy: int) -> void:
	# a curtain on a rail between the beds
	for i in 3:
		var x := 12.15 + float(i) * 3.0
		var a := Vector2(x, 26.05)
		if not _in(cx, cy, a):
			continue
		var band := Rect2(x - 0.07, 26.05, 0.14, 2.35)    # the curtain drawn along its rail, in soft folds
		c.draw_rect(Rect2(band.position + Vector2(0.05, 0.07), band.size), Color(0, 0, 0, 0.2))
		c.draw_rect(band, Color(0.58, 0.74, 0.72))
		for k in 9:
			var fy := band.position.y + 0.13 + float(k) * 0.26
			c.draw_line(Vector2(band.position.x, fy), Vector2(band.end.x, fy + 0.04), Color(0.38, 0.52, 0.5), 0.025)
		c.draw_rect(Rect2(band.position, Vector2(0.035, band.size.y)), Color(1, 1, 1, 0.25))
		c.draw_rect(band, INK, false, 0.022)
	# an IV stand by the first bed, a steel trolley by the desk
	var iv := Vector2(11.5, 28.95)
	if _in(cx, cy, iv):
		c.draw_circle(iv + Vector2(0.04, 0.05), 0.2, Color(0, 0, 0, 0.2))
		for k in 5:
			var a := TAU * float(k) / 5.0
			c.draw_line(iv, iv + Vector2(cos(a), sin(a)) * 0.18, INK, 0.035)
		c.draw_circle(iv, 0.05, STEEL_L)
		_box(c, Rect2(iv + Vector2(-0.07, -0.16), Vector2(0.14, 0.12)), Color(0.75, 0.86, 0.9, 0.9), false, 0.015)
	var tr := Rect2(15.8, 32.7, 0.9, 0.6)
	if _in(cx, cy, tr.position):
		_box(c, tr, Color(0.72, 0.74, 0.77))
		c.draw_rect(tr.grow(-0.08), Color(0.6, 0.62, 0.66))
		_box(c, Rect2(tr.position + Vector2(0.15, 0.15), Vector2(0.25, 0.18)), Color(0.9, 0.9, 0.86), false, 0.015)
		c.draw_circle(tr.position + Vector2(0.62, 0.32), 0.07, Color(0.75, 0.25, 0.22))


func _dress_workshop(c: CanvasItem, cx: int, cy: int) -> void:
	# a painted safety box round each bench, hazard stripes inside the garage door
	for b in [Vector2(29.0, 27.0), Vector2(39.0, 27.0)]:
		var bv: Vector2 = b
		if not _in(cx, cy, bv):
			continue
		var r := Rect2(bv.x - 1.15, bv.y - 0.85, 2.3, 1.85)
		c.draw_rect(r, SAFETY, false, 0.05)
	var hz := Rect2(32.0, 25.02, 5.0, 0.16)
	for k in 5:
		var piece := Rect2(hz.position.x + float(k), hz.position.y, 1.0, hz.size.y)
		if _in(cx, cy, piece.position + Vector2(0.1, 0.05)):
			_hazard(c, piece)
	# sawdust round the woodpile, a tyre, a red fuel can, bolts on the floor
	var wp := Vector2(36.0, 34.5)
	if _in(cx, cy, wp):
		for k in 22:
			var q := wp + Vector2((_r(float(k), 1.0, 320) - 0.5) * 2.6, (_r(float(k), 2.0, 321) - 0.5) * 1.3 - 0.4)
			c.draw_circle(q, 0.025 + _r(float(k), 3.0, 322) * 0.02, Color(0.78, 0.64, 0.4, 0.7))
	var ty := Vector2(42.6, 33.3)
	if _in(cx, cy, ty):
		c.draw_circle(ty + Vector2(0.05, 0.07), 0.36, Color(0, 0, 0, 0.22))
		c.draw_circle(ty, 0.36, INK)
		c.draw_circle(ty, 0.32, Color(0.16, 0.16, 0.17))
		c.draw_circle(ty, 0.15, Color(0.45, 0.46, 0.48))
		c.draw_circle(ty, 0.08, Color(0.25, 0.25, 0.27))
		for k in 8:
			var a := TAU * float(k) / 8.0
			c.draw_line(ty + Vector2(cos(a), sin(a)) * 0.2, ty + Vector2(cos(a), sin(a)) * 0.3, Color(0.3, 0.3, 0.32), 0.03)
	var jc := Rect2(30.3, 34.6, 0.34, 0.46)
	if _in(cx, cy, jc.position):
		_box(c, jc, Color(0.72, 0.2, 0.16))
		c.draw_rect(Rect2(jc.position + Vector2(0.06, -0.06), Vector2(0.12, 0.08)), INK)
		c.draw_line(jc.position + Vector2(0.06, 0.12), jc.position + Vector2(0.28, 0.36), Color(0.5, 0.12, 0.1), 0.03)
	for k in 9:
		var q := Vector2(33.0 + _r(float(k), 4.0, 323) * 6.0, 29.0 + _r(float(k), 5.0, 324) * 3.0)
		if _in(cx, cy, q):
			c.draw_circle(q, 0.03, Color(0.55, 0.56, 0.58))
			c.draw_circle(q, 0.012, INK)


func _dress_stores(c: CanvasItem, cx: int, cy: int) -> void:
	# pallets under the crates, aisle lines, hazard stripes at both doors
	for p in [Vector2(49.5, 33.5), Vector2(57.5, 33.5)]:
		var pv: Vector2 = p
		if not _in(cx, cy, pv):
			continue
		var r := Rect2(pv - Vector2(0.5, 0.48), Vector2(1.0, 0.96))
		c.draw_rect(Rect2(r.position + Vector2(0.05, 0.07), r.size), Color(0, 0, 0, 0.22))
		for k in 5:
			_box(c, Rect2(r.position.x + float(k) * 0.205, r.position.y, 0.17, r.size.y), Color(0.66, 0.53, 0.34), false, 0.018)
	for ly in [28.08, 28.92]:
		for x in range(49, 58):
			if _in(cx, cy, Vector2(float(x) + 0.5, ly)):
				c.draw_rect(Rect2(float(x) + 0.15, ly, 0.7, 0.05), Color(0.92, 0.92, 0.88, 0.55))
	for d in [Rect2(52.0, 25.02, 1.0, 0.16), Rect2(53.0, 25.02, 1.0, 0.16), Rect2(54.0, 25.02, 1.0, 0.16), Rect2(52.0, 33.82, 1.0, 0.16), Rect2(53.0, 33.82, 1.0, 0.16), Rect2(54.0, 33.82, 1.0, 0.16)]:
		var dr: Rect2 = d
		if _in(cx, cy, dr.position + Vector2(0.1, 0.05)):
			_hazard(c, dr)


# ------------------------------------------------------------ z 3: wall tops --

## Over the world's brick tops: a concrete coping along the run of each wall (light on its upper left edge, dark on its lower right), and the cell doors' barred leaves slid open over the wall.
func _walls(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var cap := Color(0.6, 0.57, 0.52)
	var lit := Color(0.76, 0.74, 0.69)
	var dk := Color(0.42, 0.40, 0.37)
	var hw := 0.15
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if not _brick(x, y):
				continue
			var m := Vector2(float(x) + 0.5, float(y) + 0.5)
			var n := _brick(x, y - 1)
			var s := _brick(x, y + 1)
			var e := _brick(x + 1, y)
			var w := _brick(x - 1, y)
			var r := Rect2(m - Vector2(hw, hw), Vector2(hw * 2.0, hw * 2.0))
			# the coping is one rect per tile: grown toward each wall it joins (to the tile edge), so the runs meet without a seam
			var x0 := (float(x) if w else r.position.x)
			var x1 := (float(x) + 1.0 if e else r.end.x)
			var y0 := (float(y) if n else r.position.y)
			var y1 := (float(y) + 1.0 if s else r.end.y)
			if e or w:
				c.draw_rect(Rect2(x0, r.position.y, x1 - x0, hw * 2.0), cap)
				c.draw_rect(Rect2(x0, r.position.y, x1 - x0, 0.035), lit)
				c.draw_rect(Rect2(x0, r.end.y - 0.035, x1 - x0, 0.035), dk)
			if n or s or not (e or w):
				c.draw_rect(Rect2(r.position.x, y0, hw * 2.0, y1 - y0), cap)
				c.draw_rect(Rect2(r.position.x, y0, 0.035, y1 - y0), lit)
				c.draw_rect(Rect2(r.end.x - 0.035, y0, 0.035, y1 - y0), dk)
			if (e or w) and (n or s):    # a junction: the cap is whole on top
				c.draw_rect(Rect2(r.position.x + 0.035, r.position.y + 0.035, hw * 2.0 - 0.07, hw * 2.0 - 0.07), cap)
			if not e and not (n or s) and w:    # the end of a run: a lit end edge
				c.draw_rect(Rect2(r.end.x - 0.035, r.position.y, 0.035, hw * 2.0), dk)
			if not w and not (n or s) and e:
				c.draw_rect(Rect2(r.position.x, r.position.y, 0.035, hw * 2.0), lit)
			if not s and not (e or w) and n:
				c.draw_rect(Rect2(r.position.x, r.end.y - 0.035, hw * 2.0, 0.035), dk)
			if not n and not (e or w) and s:
				c.draw_rect(Rect2(r.position.x, r.position.y, hw * 2.0, 0.035), lit)
			# the top edges of the wall itself: lit where the light comes from, shaded on the far sides
			if not n and not _wall(x, y - 1):
				c.draw_rect(Rect2(float(x), float(y), 1.0, 0.04), Color(1.0, 0.9, 0.8, 0.22))
			if not w and not _wall(x - 1, y):
				c.draw_rect(Rect2(float(x), float(y), 0.04, 1.0), Color(1.0, 0.9, 0.8, 0.18))
			if not s:
				c.draw_rect(Rect2(float(x), float(y) + 0.95, 1.0, 0.05), Color(0.0, 0.0, 0.0, 0.22))
			if not e:
				c.draw_rect(Rect2(float(x) + 0.95, float(y), 0.05, 1.0), Color(0.0, 0.0, 0.0, 0.18))
	_bars(c, cx, cy)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The cell doors: a barred leaf slid open over the wall east of the doorway (seen from above: a steel frame with the tops of its bars), a track across the opening, a jamb post each side, a lock box.
func _bars(c: CanvasItem, cx: int, cy: int) -> void:
	var r: Rect2i = base.CELLS
	for row in 2:
		var wy := float(r.position.y + (5 if row == 0 else 9))
		for i in 6:
			var dx := float(r.position.x + 1 + i * 4) + 1.0
			if not _in(cx, cy, Vector2(dx + 0.5, wy + 0.5)):
				continue
			var y := wy + 0.5
			# the track across the doorway
			c.draw_rect(Rect2(dx, y - 0.04, 1.0, 0.08), INK)
			c.draw_rect(Rect2(dx, y - 0.02, 1.0, 0.03), STEEL_L)
			# jambs
			for jx in [dx - 0.08, dx + 0.94]:
				_box(c, Rect2(jx, y - 0.2, 0.14, 0.4), STEEL, true, 0.025)
			# the leaf, parked over the wall to the east
			var lf := Rect2(dx + 0.98, y - 0.12, 0.96, 0.24)
			c.draw_rect(Rect2(lf.position + Vector2(0.04, 0.06), lf.size), Color(0, 0, 0, 0.3))
			c.draw_rect(lf, Color(0.2, 0.21, 0.23))
			for k in 8:
				var bp := Vector2(lf.position.x + 0.08 + float(k) * 0.115, y)
				c.draw_circle(bp, 0.045, INK)
				c.draw_circle(bp - Vector2(0.01, 0.01), 0.03, STEEL_L)
			c.draw_rect(lf, INK, false, 0.03)
			c.draw_line(lf.position + Vector2(0.02, 0.03), Vector2(lf.end.x - 0.02, lf.position.y + 0.03), Color(0.75, 0.77, 0.8, 0.7), 0.015)
			_box(c, Rect2(dx + 1.0, y - 0.1, 0.16, 0.2), Color(0.72, 0.6, 0.22), false, 0.02)    # the lock box at the leaf's edge


# -------------------------------------------------------------- the fence --

## Razor wire along the top of the chain-link and the shadow it throws (down and to the right, like every other shadow).
func _fence(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if base.kl[y * W + x] == 6 and Rect2i(base.GARDEN).has_point(Vector2i(x, y)):
				_wire(c, x, y)
				continue
			if base.kl[y * W + x] != 3:
				continue
			var horiz: bool = (x > 0 and base.kl[y * W + x - 1] != 0) or (x + 1 < W and base.kl[y * W + x + 1] != 0)
			var vert: bool = (y > 0 and base.kl[(y - 1) * W + x] != 0) or (y + 1 < H and base.kl[(y + 1) * W + x] != 0)
			var fx := float(x)
			var fy := float(y)
			if horiz and not (vert and x % 2 == 0 and false):
				c.draw_rect(Rect2(fx, fy + 0.58, 1.0, 0.1), Color(0.02, 0.02, 0.01, 0.2))    # the shadow on the ground
				_coil(c, Vector2(fx, fy + 0.42), Vector2(1.0, 0.0), x)
			elif vert:
				c.draw_rect(Rect2(fx + 0.6, fy, 0.1, 1.0), Color(0.02, 0.02, 0.01, 0.2))
				_coil(c, Vector2(fx + 0.5, fy), Vector2(0.0, 1.0), y)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The garden's wire fence on its bare soil: a wooden post in every tile, three strands to the next post, each throwing a faint shadow.
func _wire(c: CanvasItem, x: int, y: int) -> void:
	var p := Vector2(float(x) + 0.5, float(y) + 0.5)
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		if x + d.x >= W or y + d.y >= H or base.kl[(y + d.y) * W + x + d.x] != 6:
			continue
		var q := p + Vector2(d)
		var n := Vector2(-float(d.y), float(d.x))
		for k in 3:
			var o := n * (float(k) - 1.0) * 0.07
			c.draw_line(p + o + Vector2(0.04, 0.07), q + o + Vector2(0.04, 0.07), Color(0, 0, 0, 0.18), 0.028)
			c.draw_line(p + o, q + o, Color(0.6, 0.62, 0.64, 0.9), 0.024)
	c.draw_rect(Rect2(p - Vector2(0.08, 0.08) + Vector2(0.05, 0.07), Vector2(0.16, 0.16)), Color(0, 0, 0, 0.25))
	c.draw_rect(Rect2(p - Vector2(0.08, 0.08), Vector2(0.16, 0.16)), Color(0.5, 0.37, 0.22))
	c.draw_rect(Rect2(p - Vector2(0.08, 0.08), Vector2(0.16, 0.04)), Color(0.66, 0.52, 0.34))
	c.draw_rect(Rect2(p - Vector2(0.08, 0.08), Vector2(0.16, 0.16)), INK, false, 0.02)


## Concertina razor wire: overlapping loops along the fence (a dark stroke under a lit one), a barb glint here and there.
func _coil(c: CanvasItem, p: Vector2, d: Vector2, k: int) -> void:
	var n := Vector2(-d.y, d.x)
	for i in 5:
		var m := p + d * (0.1 + float(i) * 0.2)
		var pts := PackedVector2Array()
		for j in 13:
			var a := TAU * float(j) / 12.0
			pts.append(m + d * cos(a) * 0.13 + n * sin(a) * 0.14)
		var sh := PackedVector2Array()
		for q in pts:
			sh.append(q + Vector2(0.05, 0.08))
		c.draw_polyline(sh, Color(0.0, 0.0, 0.0, 0.18), 0.03)
		c.draw_polyline(pts, Color(0.06, 0.06, 0.07, 0.75), 0.04)
		c.draw_polyline(pts, Color(0.66, 0.68, 0.72, 0.95) if (i + k) % 2 == 0 else Color(0.52, 0.54, 0.58, 0.95), 0.018)
		if (i + k) % 3 == 0:
			c.draw_circle(m - n * 0.1 - d * 0.04, 0.02, Color(0.92, 0.94, 0.98))


## The gate: two steel rolling leaves with ribs, hazard stripes where they meet, a chain and a padlock, razor wire on top. `g` is the top left (pixels) of the gate, `leaf` the size of one leaf.
static func draw_gate(c: CanvasItem, g: Vector2, leaf: Vector2, gap: float) -> void:
	for side in 2:
		var o := g + Vector2((leaf.x + gap) * float(side), 0.0)
		c.draw_rect(Rect2(o + Vector2(4, 6), leaf), Color(0, 0, 0, 0.30))    # shadow
		c.draw_rect(Rect2(o, leaf), Color(0.36, 0.39, 0.42))
		var ribs := 7
		for i in ribs:
			var yy := o.y + 4.0 + float(i) * (leaf.y - 8.0) / float(ribs)
			c.draw_line(Vector2(o.x + 3, yy + 5), Vector2(o.x + leaf.x - 3, yy + 5), Color(0.17, 0.19, 0.21), 2.0)
			c.draw_line(Vector2(o.x + 3, yy + 3), Vector2(o.x + leaf.x - 3, yy + 3), Color(0.55, 0.58, 0.62, 0.8), 1.0)
		c.draw_rect(Rect2(o, leaf), Color(0.08, 0.09, 0.1), false, 3.0)
		c.draw_line(o + Vector2(2, 2), o + Vector2(leaf.x - 2, 2), Color(0.7, 0.73, 0.78, 0.8), 1.0)
		# hazard stripes on the edge where the leaves meet
		var ex := o.x + (leaf.x - 12.0 if side == 0 else 0.0)
		for i in 8:
			var col := Color(0.92, 0.74, 0.12) if i % 2 == 0 else Color(0.08, 0.08, 0.08)
			c.draw_rect(Rect2(ex, o.y + float(i) * leaf.y / 8.0, 12.0, leaf.y / 8.0), col)
		c.draw_rect(Rect2(ex, o.y, 12.0, leaf.y), Color(0, 0, 0, 0.12))
		# the track the leaf rolls on
		c.draw_rect(Rect2(o.x - (6.0 if side == 0 else 0.0), o.y + leaf.y - 5.0, leaf.x + 6.0, 4.0), Color(0.1, 0.1, 0.11, 0.8))
		for wx in [0.18, 0.82]:
			c.draw_circle(Vector2(o.x + leaf.x * wx, o.y + leaf.y - 3.0), 3.2, Color(0.2, 0.2, 0.22))
		# razor wire along the top
		var pa := PackedVector2Array()
		var pb := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0
			var ph := t * TAU * 6.0
			pa.append(Vector2(o.x + t * leaf.x, o.y - 3.0 + sin(ph) * 3.0))
			pb.append(Vector2(o.x + t * leaf.x, o.y - 3.0 + sin(ph + PI) * 3.0))
		c.draw_polyline(pa, Color(0.75, 0.77, 0.82), 1.2)
		c.draw_polyline(pb, Color(0.5, 0.52, 0.56), 1.2)
	# chain across the middle and a padlock
	var m := g + Vector2(leaf.x + gap * 0.5, leaf.y * 0.5)
	for i in 6:
		var a := m + Vector2(-13.0 + float(i) * 5.0, sin(float(i) * 1.7) * 2.0)
		c.draw_circle(a, 2.4, Color(0.1, 0.1, 0.1))
		c.draw_circle(a, 1.5, Color(0.55, 0.57, 0.6))
	c.draw_rect(Rect2(m + Vector2(-5, -1), Vector2(10, 11)), Color(0.1, 0.08, 0.04))
	c.draw_rect(Rect2(m + Vector2(-4, 0), Vector2(8, 9)), Color(0.78, 0.62, 0.2))
	c.draw_arc(m + Vector2(0, -1), 4.0, PI, TAU, 8, Color(0.7, 0.72, 0.76), 1.6)
	# a no-entry plate on the west leaf
	var sp := g + Vector2(leaf.x * 0.32, leaf.y * 0.3)
	c.draw_rect(Rect2(sp + Vector2(2, 3), Vector2(22, 14)), Color(0, 0, 0, 0.3))
	c.draw_rect(Rect2(sp, Vector2(22, 14)), Color(0.78, 0.18, 0.14))
	c.draw_rect(Rect2(sp + Vector2(4, 6), Vector2(14, 3)), Color(0.95, 0.93, 0.88))
	c.draw_rect(Rect2(sp, Vector2(22, 14)), Color(0.08, 0.06, 0.05), false, 1.5)
	# a concrete pillar at each end, the leaves roll behind them
	for px in [g.x - 16.0, g.x + leaf.x * 2.0 + gap - 2.0]:
		var pr := Rect2(px, g.y - 10.0, 18.0, leaf.y + 16.0)
		c.draw_rect(Rect2(pr.position + Vector2(6, 8), pr.size), Color(0, 0, 0, 0.3))
		c.draw_rect(pr, Color(0.6, 0.58, 0.54))
		c.draw_rect(Rect2(pr.position, Vector2(pr.size.x, 4)), Color(0.78, 0.76, 0.72))
		c.draw_rect(Rect2(pr.position, Vector2(4, pr.size.y)), Color(0.7, 0.68, 0.64))
		c.draw_rect(Rect2(pr.end.x - 4, pr.position.y, 4, pr.size.y), Color(0.45, 0.43, 0.4))
		c.draw_rect(Rect2(pr.position + Vector2(5, 6), Vector2(8, 8)), Color(0.5, 0.48, 0.45))    # the cap's bolt plate
		c.draw_rect(pr, Color(0.08, 0.09, 0.1), false, 2.5)
