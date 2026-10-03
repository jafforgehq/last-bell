## Draws a road of the live drive (round 21, scripts/drive/road_gen.gd) so it can be looked at: the real world (scripts/world.gd) built
## from the road's data, the trees, the roadblocks' wrecks (the scene draws these) and, unless `--bare`, the path, the stops, the gaps,
## the dead, the start and the exit marked on it, saved as a PNG. Windowed (headless cannot render), from the repo root:
##
##   Godot --path . --script res://tools/road_preview.gd -- --place=pharmacy --seed=3 --out=/tmp/road.png
##
## --place=<place id or kind of assets/data/town.json> (default pharmacy)  --seed=N  --leg=there|home  --kind=<sedan|pickup|van|bus|foot>
## --danger=N (the place's by default)  --events=<ids joined by commas: ambush,roadblock,survivor,wreck_supplies,breakdown,herd,
## fuel_stash,checkpoint,smoke>, spaced along the road (default ambush,roadblock,survivor,checkpoint; --events=none for a bare road)
## --len=N (rows; else made from the kind's cruise and 80 minutes)  --hour=H (the sky of that hour, a headlight cone at night)
## --from=<row> --rows=N (a window of the strip; else all of it)  --overview (the whole strip in side-by-side columns, small)
## --scale=0.4 (pixels to the tile are 64 x scale)  --bare (no markers)  --ascii (the strip as text, add --headless)  --stats
extends SceneTree

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const RoadGen := preload("res://scripts/drive/road_gen.gd")
const Lighting := preload("res://scripts/render/lighting.gd")

const EVENT_KIND := {"ambush": "dead", "roadblock": "block", "survivor": "stop", "wreck_supplies": "stop", "breakdown": "forced", "herd": "dead", "fuel_stash": "stop", "checkpoint": "stop", "smoke": "stop"}
const CRUISE := {"sedan": 7.68, "pickup": 7.04, "van": 7.04, "bus": 5.76, "foot": 3.2}

var _site: Dictionary
var _vp: SubViewport
var _marks: Node2D
var _cam: Camera2D
var _scale := 0.4


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
		if a == "--%s" % name:
			return "1"
	return default


static func place_for(key: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	for p in parsed.places:
		if String(p.id) == key:
			return p
	for p in parsed.places:
		if String(p.kind) == key:
			return p
	return {"id": key, "name": key.capitalize(), "kind": key, "danger": 2}


## A plan made by hand: the events spaced along the road (the shape of RoadEvents.plan).
static func plan_of(ids: Array, seed_value: int) -> Array:
	var out: Array = []
	var n := ids.size()
	for i in n:
		var id := String(ids[i])
		var at := 0.14 + (0.86 - 0.14) * (float(i) / float(maxi(1, n - 1))) if n > 1 else 0.5
		out.append({"uid": "e%d" % (i + 1), "id": id, "kind": String(EVENT_KIND.get(id, "stop")), "at": clampf(at, 0.12, 0.9), "seed": seed_value + i, "night": false, "state": "pending", "def": {"title": id}})
	return out


func _run() -> void:
	var place := place_for(_arg("place", "pharmacy"))
	var seed_value := int(_arg("seed", "1"))
	var leg := _arg("leg", "there")
	var kind_arg := _arg("kind", "pickup")
	var kind := "" if kind_arg == "foot" else kind_arg
	var danger := int(_arg("danger", str(int(place.get("danger", 1)))))
	var ids_text := _arg("events", "ambush,roadblock,survivor,checkpoint")
	var ids: Array = [] if ids_text == "none" else Array(ids_text.split(",", false))
	var cruise := float(CRUISE.get(kind_arg, 7.0))
	var len_t := int(_arg("len", "0"))
	if len_t <= 0:
		len_t = mini(roundi(clampf(80.0, 30.0, 90.0) * cruise), RoadGen.MAX_STRIP)
	var hour := float(_arg("hour", "10"))
	var ctx := {"kind": kind, "road_min": 80.0, "cruise": cruise, "len": len_t, "plan": plan_of(ids, seed_value), "danger": danger, "hour": hour, "leg": leg}
	var t0 := Time.get_ticks_msec()
	_site = RoadGen.make(place, seed_value, leg, ctx)
	var ms := Time.get_ticks_msec() - t0
	if _arg("stats") != "" or _arg("ascii") != "":
		_stats(ms)
	if _arg("ascii") != "":
		print(_ascii())
	var out := _arg("out", "")
	if out == "":
		quit()
		return
	_scale = float(_arg("scale", "0.4"))
	var size: Vector2i = _site.size
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.065, 0.055)
	bg.size = Vector2(size.x * 64, size.y * 64)
	_vp.add_child(bg)
	var world := World.new()
	_vp.add_child(world)
	world.build(_site.data)
	for tr in _site.data.trees:
		var s := Sprite2D.new()
		var box: Array = _site.data.tree.box
		var dens := float(_site.data.tree.density)
		s.texture = GD.tex(tr.file)
		s.centered = false
		s.offset = Vector2(box[0], box[1]) * dens
		s.scale = Vector2.ONE * (64.0 / dens)
		s.position = Vector2(tr.x, tr.y) * 64.0
		s.z_index = 6
		world.add_child(s)
	for w in _site.road.dyn:
		var s := Sprite2D.new()
		s.texture = GD.tex(String(w.file))
		var sz: Vector2 = w.size
		var tex_size := Vector2(s.texture.get_width(), s.texture.get_height())
		s.scale = Vector2(sz.x * 64.0 / tex_size.x, sz.y * 64.0 / tex_size.y)
		s.position = Vector2(w.pos) * 64.0
		s.rotation = float(w.rot)
		s.z_index = 5
		world.add_child(s)
	if _arg("bare") == "":
		_marks = Node2D.new()
		_marks.z_index = 20
		_marks.draw.connect(_draw_marks)
		world.add_child(_marks)
		_marks.queue_redraw()
	# the sky of the hour (a night has a headlight cone at the start)
	var sky := CanvasModulate.new()
	sky.color = _sky(hour)
	_vp.add_child(sky)
	if hour < 6.0 or hour > 19.5:
		var cone := Polygon2D.new()
		var st: Vector2 = _site.road.start
		var d := float(_site.road.dir)
		var pts := PackedVector2Array([Vector2(-0.6, 0.0), Vector2(0.6, 0.0), Vector2(5.5, d * 24.0), Vector2(-5.5, d * 24.0)])
		for i in pts.size():
			pts[i] = (st + Vector2(pts[i].x, pts[i].y)) * 64.0
		cone.polygon = pts
		cone.color = Color(1.0, 0.92, 0.6, 0.35)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		cone.material = mat
		cone.z_index = 30
		world.add_child(cone)
	_cam = Camera2D.new()
	_vp.add_child(_cam)
	_cam.make_current()
	var img: Image
	if _arg("overview") != "":
		img = await _overview()
	else:
		var from := int(_arg("from", "0"))
		var rows := int(_arg("rows", str(size.y - from)))
		img = await _capture(from, mini(rows, size.y - from))
	img.save_png(out)
	print("saved %s (%dx%d), made in %d ms" % [out, img.get_width(), img.get_height(), ms])
	quit()


## The rows from..from+rows of the strip, drawn at the scale.
func _capture(from: int, rows: int) -> Image:
	var size: Vector2i = _site.size
	_vp.size = Vector2i(int(float(size.x) * 64.0 * _scale), int(float(rows) * 64.0 * _scale))
	_cam.zoom = Vector2(_scale, _scale)
	_cam.position = Vector2(float(size.x) * 32.0, (float(from) + float(rows) / 2.0) * 64.0)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


## The whole strip cut into columns, side by side.
func _overview() -> Image:
	var size: Vector2i = _site.size
	var cols := clampi(int(ceil(float(size.y) / 190.0)), 1, 5)
	var per := int(ceil(float(size.y) / float(cols)))
	var tile_px := int(float(size.x) * 64.0 * _scale)
	var out := Image.create(cols * (tile_px + 10), int(float(per) * 64.0 * _scale), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.02, 0.02, 0.02))
	for i in cols:
		var from := i * per
		var rows := mini(per, size.y - from)
		var part := await _capture(from, rows)
		part.convert(Image.FORMAT_RGBA8)
		out.blit_rect(part, Rect2i(0, 0, part.get_width(), part.get_height()), Vector2i(i * (tile_px + 10), 0))
	return out


func _sky(hour: float) -> Color:
	var keys: Array = Lighting.SKY
	var h := fposmod(hour, 24.0)
	for i in range(1, keys.size()):
		if h <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var t := (h - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1] as Color, t)
	return keys[keys.size() - 1][1]


func _draw_marks() -> void:
	var T := 64.0
	var font := ThemeDB.fallback_font
	var road: Dictionary = _site.road
	# the centre line and the path
	var cl: PackedVector2Array = road.centerline
	for i in range(1, cl.size()):
		_marks.draw_line(cl[i - 1] * T, cl[i] * T, Color(1, 1, 1, 0.25), 2.0)
	var path: PackedVector2Array = road.path
	for i in range(1, path.size()):
		_marks.draw_line(path[i - 1] * T, path[i] * T, Color(0.2, 0.9, 1.0, 0.8), 3.0)
	for z in _site.dead:
		var p: Vector2 = z.pos
		var col := Color(0.9, 0.2, 0.2, 0.85)
		var rad := 9.0
		if z.kind == "runner":
			col = Color(1.0, 0.55, 0.1, 0.9)
		elif z.kind == "brute":
			col = Color(0.7, 0.1, 0.8, 0.9)
			rad = 15.0
		_marks.draw_circle(p * T, rad, col)
		if z.state == "wander":
			_marks.draw_arc(p * T, rad + 4.0, 0, TAU, 16, Color(1, 1, 1, 0.8), 2.0)
	for s in road.slots:
		var a: Vector2 = s.anchor
		_marks.draw_circle(a * T, 12.0, Color(1.0, 0.85, 0.1, 0.9))
		_marks.draw_string(font, a * T + Vector2(14, -14), "%s %s" % [s.uid, s.id], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.95, 0.5))
		if s.gap is Rect2:
			var g: Rect2 = s.gap
			_marks.draw_rect(Rect2(g.position * T, g.size * T), Color(0.2, 1.0, 0.3, 0.9), false, 3.0)
		var sp: Vector2 = s.spawn
		for f in s.get("figures", []):
			_marks.draw_circle(Vector2(f) * T, 10.0, Color(1.0, 0.2, 0.9, 0.95))
		for pr in s.get("props", []):
			_marks.draw_circle(Vector2(pr.pos) * T, 5.0, Color(1.0, 0.5, 0.1, 0.9))
		if String(s.id) in ["ambush", "herd"]:
			_marks.draw_line((sp - Vector2(6, 0)) * T, (sp + Vector2(6, 0)) * T, Color(1, 0.2, 0.2, 0.6), 4.0)
			_marks.draw_circle(sp * T, 14.0, Color(1, 0.1, 0.1, 0.7))
	var e: Vector2 = _site.entry
	_marks.draw_circle(e * T, 12.0, Color(0.2, 1.0, 0.3, 0.9))
	_marks.draw_rect(Rect2(_site.exit.position * T, _site.exit.size * T), Color(0.2, 1.0, 0.3, 0.8), false, 3.0)


func _stats(ms: int) -> void:
	var kinds := {}
	for z in _site.dead:
		kinds[z.kind] = int(kinds.get(z.kind, 0)) + 1
	var cars := 0
	for o in _site.data.objects:
		if String(o.kind) in ["car_h", "car_v", "car_police", "van_h", "pickup_v", "bus_h", "bus_v"]:
			cars += 1
	print("%s (%s, %s) seed %d leg %s: %s tiles, made in %d ms" % [_site.name, _site.kind, _site.road.style, _site.seed, _site.road.leg, str(_site.size), ms])
	print("  road len %.1f, start %s end %s dir %d, exit %s" % [_site.road.len, str(_site.road.start), str(_site.road.end), _site.road.dir, str(_site.exit)])
	print("  objects %d (cars %d) trees %d dead %d %s wrecks %d" % [_site.data.objects.size(), cars, _site.data.trees.size(), _site.dead.size(), str(kinds), _site.road.dyn.size()])
	for s in _site.road.slots:
		print("  slot %s %s y %.1f anchor %s gap %s figure %s props %d" % [s.uid, s.id, s.y, str(s.anchor), str(s.gap), str(s.figure), s.get("props", []).size()])


## The strip as text: # shut, . open, = carriageway, o wreck of a block, * the path, S start, E end.
func _ascii() -> String:
	var d: Dictionary = _site.data
	var W := int(d.W)
	var H := int(d.H)
	var grid: Array = []
	for y in H:
		var row: Array = []
		for x in W:
			var ch := "."
			if int(d.terrain[y * W + x]) == 1:
				ch = "="
			if int(d.solidP[y * W + x]) != 0:
				ch = "#"
			row.append(ch)
		grid.append(row)
	for w in _site.road.dyn:
		for idx in w.tiles:
			grid[int(idx) / W][int(idx) % W] = "o"
	for p in _site.road.path:
		var x := int(p.x)
		var y := int(p.y)
		if y >= 0 and y < H and x >= 0 and x < W and grid[y][x] in ["=", "."]:
			grid[y][x] = "*"
	for z in _site.dead:
		var p: Vector2 = z.pos
		if grid[int(p.y)][int(p.x)] in ["=", ".", "*"]:
			grid[int(p.y)][int(p.x)] = {"walker": "z", "runner": "r", "brute": "&"}[z.kind]
	var lines: Array = []
	for y in H:
		lines.append("".join(grid[y]))
	return "\n".join(lines)
