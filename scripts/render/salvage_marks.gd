## SALVAGE in the world (One House): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_event(e)`). It reads the rules
## (`sim.salvage`, scripts/town/salvage.gd: the stripped pieces, the `stripped` event) and writes nothing in them.
##
##   - THE PIECE GOES. A stripped piece is taken out of the world's drawing: its index leaves the list of the chunk layer (a street piece) or of the house (a piece inside) that draws it, and
##     that one node is drawn again (a house's furniture node: a few draws; a chunk layer: once, about as much as its first draw). Nothing is masked and the draw code is not touched. A loaded game
##     does the same for every piece of the saved set when the view is made, before anything has been drawn: the world is made from the seed again.
##   - THE RUBBLE. Where it stood a small pile is left (planks, sheets of metal or lumps of stuffing by what the piece was made of, assets/data/salvage.json `rubble`): one Node2D for each 32 x 32 tiles
##     that has any, under the people (z 2), drawn again only when a piece is added.
##   - THE POP. "+3 scrap" rises from the spot and flies to the stores' scrap (and a grey "Picked clean" under it when that was the last the house gave): 1.4 s, a fixed pool of six, drawn on the HUD
##     like the loot pops (scripts/ui/search_marks.gd). REDUCE MOTION / REDUCE FLASHES: it stands above the spot, still.
##   - THE SOUND. While the avatar strips, a hammer, a scrape or a creak by what the piece is made of every 1.3 s; a thud or a clank when it is done (the existing samples through `sound.play`).
## COST. Nothing is drawn but when a piece is stripped or a pop is up; `on_frame` is a counter and a session test.
## STAGING. `--salvage=<kind>[:idle|:hold[:F]|:done[:K]|:after]` (scripts/ui/salvage_stage.gd, see the README).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Stage := preload("res://scripts/ui/salvage_stage.gd")
const DATA_PATH := "res://assets/data/salvage.json"
const POP_COUNT := 6
const POP_RISE := 26.0
const POP_PX := 17
const CELL := 32

const SOUNDS := {
	"salvage_work_wood": ["hammer_1", "scrape_wood_0", "hammer_2", "scrape_wood_1"],
	"salvage_work_metal": ["scrape_metal_0", "hit_plate_0", "scrape_metal_1"],
	"salvage_work_cloth": ["creak_0", "scrape_wood_1", "creak_1"],
	"salvage_done_wood": ["thud_0", "thud_1"],
	"salvage_done_metal": ["hit_plate_1", "hit_plate_2"],
	"salvage_done_cloth": ["thud_1", "thud_0"],
}

var main
var hud
var sim
var world
var salv
var pop_layer: Control
var pops: Array = []
## What the view did, for the pictures and the reports: pieces taken out of the drawing, the rubble piles, the pops drawn at the last frame.
var dropped := 0
var piles := 0
var drawn_pops := 0
var played: Array = []

var _root: Node2D
var _cells := {}
var _cfg := {}
var _frames := 0
var _calm := false
var _work_t := 0.0
var _pop_s := 1.4
var _sound
var _cost := false
var _cost_done := false
var _ft: Array = []
var _last_us := 0
var _strip_frame := -1
var _take_us := 0


class Pop:
	var alive := false
	var text := ""
	var sub := ""
	var color := Color.WHITE
	var at := Vector2.ZERO
	var age := 0.0
	var target := Vector2.ZERO
	var flies := true


## One 32 x 32 tile cell of rubble: the piles of its pieces.
class Rubble:
	extends Node2D
	const TILE := 64.0
	var items: Array = []
	var pal := {}

	func _draw() -> void:
		for it in items:
			_pile(it)

	func _pile(it: Dictionary) -> void:
		var stuff := String(it.stuff)
		var colours: Dictionary = pal.get(stuff, pal.get("wood", {}))
		var fills: Array = colours.get("fill", ["8a6a45"])
		var edge := Color(String(colours.get("edge", "221a13")))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(it.idx) * 7919 + 13
		var cx: float = it.cx
		var cy: float = it.cy
		var w: float = it.w
		var h: float = it.h
		# a scuff where it stood
		var scuff := PackedVector2Array()
		for k in 12:
			var a := TAU * float(k) / 12.0
			scuff.append(Vector2(cx + cos(a) * w * 0.46, cy + sin(a) * h * 0.46) * TILE)
		draw_colored_polygon(scuff, Color(0.08, 0.06, 0.04, 0.22))
		var n := clampi(int(w * h * 2.4) + 2, 3, 8)
		for k in n:
			var col := Color(String(fills[rng.randi() % fills.size()]))
			var at := Vector2(cx + rng.randf_range(-0.42, 0.42) * w, cy + rng.randf_range(-0.38, 0.38) * h) * TILE
			var rot := rng.randf() * PI
			var pts: PackedVector2Array
			match stuff:
				"wood":
					pts = _quad(at, rot, rng.randf_range(0.3, 0.56) * TILE, rng.randf_range(0.07, 0.11) * TILE)
				"metal":
					pts = _blob(at, rot, rng.randf_range(0.13, 0.26) * TILE, 5, rng)
				_:
					pts = _blob(at, rot, rng.randf_range(0.13, 0.24) * TILE, 8, rng)
			var shadow := PackedVector2Array()
			for p in pts:
				shadow.append(p + Vector2(2.0, 3.0))
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.24))
			draw_colored_polygon(pts, col)
			var loop := pts.duplicate()
			loop.append(pts[0])
			draw_polyline(loop, edge, 1.6, true)
			if stuff == "metal":
				draw_line(pts[0].lerp(pts[1], 0.2), pts[0].lerp(pts[1], 0.7), Color(1, 1, 1, 0.35), 1.4)

	static func _quad(at: Vector2, rot: float, len_px: float, wid_px: float) -> PackedVector2Array:
		var ax := Vector2(cos(rot), sin(rot))
		var ay := Vector2(-ax.y, ax.x)
		return PackedVector2Array([at - ax * len_px * 0.5 - ay * wid_px, at + ax * len_px * 0.5 - ay * wid_px, at + ax * len_px * 0.5 + ay * wid_px, at - ax * len_px * 0.5 + ay * wid_px])

	static func _blob(at: Vector2, rot: float, r: float, sides: int, rng: RandomNumberGenerator) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in sides:
			var a := rot + TAU * float(k) / float(sides)
			pts.append(at + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.65, 1.15))
		return pts


func on_ready(main_node) -> void:
	main = main_node
	sim = main.get("sim")
	hud = main.get("hud")
	world = main.get("world")
	_sound = main.get("sound")
	salv = sim.get("salvage") if sim != null else null
	if salv == null or world == null:
		return
	_read_cfg()
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--salvage-cost":
			_cost = true
	for i in POP_COUNT:
		pops.append(Pop.new())
	_root = Node2D.new()
	_root.name = "Rubble"
	_root.z_index = 2
	world.add_child(_root)
	if hud != null:
		pop_layer = Control.new()
		pop_layer.name = "SalvagePops"
		pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pop_layer.draw.connect(_draw_pops)
		hud.add_child(pop_layer)
	_load_sounds()
	# a loaded game: what was stripped is gone from the first frame (the world is made from the seed)
	for id in salv.stripped:
		_take_out(String(id))


func _read_cfg() -> void:
	if FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_cfg = parsed
	var pal = _cfg.get("rubble", {})
	_pop_s = float(_cfg.get("pop", {}).get("seconds", 1.4)) if typeof(_cfg.get("pop")) == TYPE_DICTIONARY else 1.4
	if typeof(pal) != TYPE_DICTIONARY:
		_cfg["rubble"] = {}


func _load_sounds() -> void:
	if _sound == null or _sound.get("streams") == null:
		return
	for name in SOUNDS:
		var list: Array = []
		for f in SOUNDS[name]:
			var path := "res://assets/audio/%s.wav" % String(f)
			if ResourceLoader.exists(path):
				var s = load(path)
				if s != null:
					list.append(s)
		if not list.is_empty():
			_sound.streams[name] = list


# ------------------------------------------------------------------------------ events --

func on_event(e: Dictionary) -> void:
	if salv == null or String(e.get("type", "")) != "stripped":
		return
	var id := String(e.get("piece", ""))
	var pc: Dictionary = salv.piece(id)
	var t0 := Time.get_ticks_usec()
	_take_out(id)
	_take_us = Time.get_ticks_usec() - t0
	_strip_frame = _frames
	_pop(e)
	var stuff := String(pc.get("stuff", "wood"))
	_play("salvage_done_" + stuff, float(_cfg.get("sound", {}).get("done_level", 0.6)))
	_work_t = 0.0


func on_frame(dt: float) -> void:
	_frames += 1
	if salv == null:
		return
	if _cost:
		var now := Time.get_ticks_usec()
		if _last_us > 0 and _frames > 30:
			_ft.append(now - _last_us)
		_last_us = now
		_cost_report()
	Stage.on_frame(main, _frames)
	_calm = Prefs.on("ui", "reduce_motion") or Prefs.on("ui", "reduce_flashes")
	var live := false
	for p in pops:
		if p.alive:
			p.age += dt
			if p.age >= _pop_s:
				p.alive = false
			else:
				live = true
	if pop_layer != null and (live or drawn_pops > 0):
		pop_layer.queue_redraw()
	# the work sounds: while the avatar's hands are at a piece
	var pc: Dictionary = salv.session_piece()
	if pc.is_empty():
		_work_t = 0.0
		return
	_work_t -= dt
	if _work_t <= 0.0:
		_work_t = float(_cfg.get("sound", {}).get("work_every", 1.3))
		_play("salvage_work_" + String(pc.stuff), float(_cfg.get("sound", {}).get("work_level", 0.32)))


# -------------------------------------------------------------------------------- cost --

## `--salvage-cost` (with `--shot`): two frames before the shot, one line: the milliseconds of the frames (median; the longest of the five after a strip), what taking the piece out of the world
## cost (microseconds), and what E's candidates cost with this part and without it (microseconds a call, 300 calls each way, in the house the avatar stands in).
func _cost_report() -> void:
	if _cost_done or String(main.get("shot_path")) == "":
		return
	if int(main.get("shot_frames")) - int(main.get("frame_count")) > 2 or _ft.size() < 5:
		return
	_cost_done = true
	var sorted := _ft.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2]) / 1000.0
	var worst := 0.0
	if _strip_frame > 0:
		var from := _strip_frame - 31
		for i in range(maxi(from, 0), mini(from + 5, _ft.size())):
			worst = maxf(worst, float(_ft[i]) / 1000.0)
	var n := 300
	salv.enabled = true
	var t0 := Time.get_ticks_usec()
	for i in n:
		sim.interact.candidates()
	var with_us := float(Time.get_ticks_usec() - t0) / float(n)
	salv.enabled = false
	t0 = Time.get_ticks_usec()
	for i in n:
		sim.interact.candidates()
	var without_us := float(Time.get_ticks_usec() - t0) / float(n)
	salv.enabled = true
	print("salvage cost: frame median %.1f ms, longest of the 5 frames after a strip %.1f ms; taking a piece out of the world %d us; interact.candidates() %.1f us with salvage, %.1f us without" % [median, worst, _take_us, with_us, without_us])


func _play(name: String, level: float) -> void:
	if _sound == null or not _sound.has_method("play") or _sound.get("streams") == null or not _sound.streams.has(name):
		return
	played.append(name)
	if played.size() > 32:
		played.pop_front()
	_sound.play(name, level)


# ----------------------------------------------------------------------- the world's drawing --

## Takes piece `id` out of the world's drawing and leaves its rubble.
func _take_out(id: String) -> void:
	var pc: Dictionary = salv.piece(id)
	if pc.is_empty():
		return
	_remove_from_lists(int(pc.idx))
	_add_rubble(pc)


func _remove_from_lists(idx: int) -> void:
	var o: Dictionary = world.d.objects[idx]
	var house := int(o.get("in", -1))
	if house >= 0:
		var list: PackedInt32Array = world.house_objs.get(house, PackedInt32Array())
		var k := list.find(idx)
		if k >= 0:
			list.remove_at(k)
			world.house_objs[house] = list
			dropped += 1
		var node = world.house_nodes.get(house)
		if node != null and is_instance_valid(node):
			node.items = list
			node.queue_redraw()
		return
	var layer := clampi(int(o.layer), 1, 4)
	var cx := clampi(int(float(o.cx)) >> 5, 0, world.chunks_x - 1)
	var cy := clampi(int(float(o.cy)) >> 5, 0, world.chunks_y - 1)
	var ci: int = cy * world.chunks_x + cx
	var lists: Array = world.chunk_objs[ci]
	var l: PackedInt32Array = lists[layer]
	var j := l.find(idx)
	if j >= 0:
		l.remove_at(j)
		lists[layer] = l
		dropped += 1
	var holder: Node = world.chunks[ci].node
	for n in holder.get_children():
		if int(n.get("layer")) == layer:
			n.queue_redraw()


func _add_rubble(pc: Dictionary) -> void:
	var key := floori(float(pc.cy) / float(CELL)) * 1000 + floori(float(pc.cx) / float(CELL))
	var cell: Rubble = _cells.get(key)
	if cell == null:
		cell = Rubble.new()
		cell.name = "Rubble%d" % key
		cell.pal = _cfg.get("rubble", {})
		_root.add_child(cell)
		_cells[key] = cell
	var rect: Rect2i = pc.rect
	cell.items.append({"idx": int(pc.idx), "stuff": String(pc.stuff), "cx": float(pc.cx), "cy": float(pc.cy), "w": float(rect.size.x), "h": float(rect.size.y)})
	cell.queue_redraw()
	piles += 1


# ------------------------------------------------------------------------------- the pop --

func _spawn(text: String, sub: String, col: Color, at: Vector2, fly: bool) -> void:
	var p: Pop = null
	for q in pops:
		if not q.alive:
			p = q
			break
	if p == null:
		p = pops[0]
	p.alive = true
	p.text = text
	p.sub = sub
	p.color = col
	p.at = at
	p.age = 0.0
	p.flies = fly
	p.target = Vector2(-1000.0, -1000.0)
	if fly and hud != null and hud.has_method("anchor_rect"):
		var r: Rect2 = hud.anchor_rect("stores.scrap")
		if r.size == Vector2.ZERO:
			r = hud.anchor_rect("stores")
		if r.size != Vector2.ZERO:
			p.target = r.get_center()
		else:
			p.flies = false


func _pop(e: Dictionary) -> void:
	if pop_layer == null or hud == null:
		return
	var n := int(e.get("scrap", 0))
	if n <= 0:
		return
	var at := Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	_spawn("+%d scrap" % n, "Picked clean" if bool(e.get("clean", false)) else "", hud.ACCENT, at, true)


func screen_of(tile: Vector2) -> Vector2:
	var vp := pop_layer.size if pop_layer != null else Vector2(1280, 800)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (tile - cam) * z + vp * 0.5


func _draw_pops() -> void:
	drawn_pops = 0
	if hud == null or main == null:
		return
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	for p in pops:
		if p.alive:
			_draw_pop(p, z)
			drawn_pops += 1


func _draw_pop(p: Pop, z: float) -> void:
	var start := screen_of(p.at) + Vector2(0.0, -minf(0.3 * z, 24.0))
	var pos: Vector2
	var alpha := 1.0
	var px := POP_PX
	var fly_at := _pop_s * 0.55
	if _calm or not p.flies:
		var rise := POP_RISE if _calm else POP_RISE * (1.0 - pow(1.0 - clampf(p.age / 0.5, 0.0, 1.0), 2.0))
		pos = start + Vector2(0.0, -rise)
		if not _calm:
			alpha = clampf((_pop_s - p.age) / 0.4, 0.0, 1.0)
	else:
		var rise2 := POP_RISE * (1.0 - pow(1.0 - clampf(p.age / 0.5, 0.0, 1.0), 2.0))
		pos = start + Vector2(0.0, -rise2)
		var f := clampf((p.age - fly_at) / maxf(_pop_s - fly_at, 0.01), 0.0, 1.0)
		if f > 0.0:
			pos = pos.lerp(p.target, f * f)
			px = maxi(12, roundi(float(POP_PX) * (1.0 - 0.3 * f)))
			alpha = 1.0 - smoothstep(0.65, 1.0, f)
		alpha *= clampf(p.age / 0.1, 0.0, 1.0)
	var font := Fonts.cond(700)
	var w := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := pos - Vector2(w * 0.5, 0.0)
	pop_layer.draw_string_outline(font, at, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 5, Color(0.0, 0.0, 0.0, 0.85 * alpha))
	pop_layer.draw_string(font, at, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(p.color, alpha))
	if p.sub != "":
		# (under it, still: it does not fly with the number; it stays where the piece was and fades)
		var sub_px := 13
		var sw := font.get_string_size(p.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_px).x
		var sub_at := start + Vector2(-sw * 0.5, 10.0)
		var sa := clampf((_pop_s - p.age) / 0.5, 0.0, 1.0) * clampf(p.age / 0.15, 0.0, 1.0)
		pop_layer.draw_string_outline(font, sub_at, p.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_px, 4, Color(0.0, 0.0, 0.0, 0.8 * sa))
		pop_layer.draw_string(font, sub_at, p.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_px, Color(hud.INK2, sa))
