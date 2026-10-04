## The base's perimeter on the screen (One House, PV), a view part of the town facade (scripts/town/town_game.gd VIEW_PARTS). `sim.perimeter` (scripts/town/perimeter.gd) knows what
## stands round the claimed house; nothing drew it. This part reads `sections()` and `slots()` and draws it from the art kit (assets/data/town_art.json, "fortify", through TownArt):
##
##  FENCE. Each fence cell is a cell of the kit's autotile atlas chosen by which sides of it join another standing fence or gate cell (N 1, E 2, S 4, W 8), so a run has its posts at
##  the ends and the corners join: a ring looks like a fence. The look follows the section's hit points (the colony's own `state`): 0 whole = the built look, 1 (under 66%) = a part of
##  the cells show damage, 2 (under 33%) = all of them, 3 down = the cells are gone and what is left lies on the ground: a clear gap (and the cells beside it end in a post). The plain
##  fence is the wooden palisade, the reinforced kit (`fence_strong`) the steel-sheet one.
##  GATE. The kit's gate, closed or open (`perimeter.gate_open()`), built or damaged. BARRED DOORS. Planks over each door of the house (`barricade_door`), the plank kit adds a second
##  layer, a door that has fallen shows splinters. TOWER. A deck on stilts over its slot tile and the post tile of the shooter (the post is the layout's), under the people so the
##  shooter on it is seen. FLOODLIGHT. A pole standing among the people (sorted by its foot, in `main.entities`) with a PointLight2D that burns at dusk and a glow round the head.
##  BUILD SITES. A slot that is ordered or going up shows what it will be as a ghost (a fence fills in from one end as the work is done), under a progress ring at its middle.
##  OPEN SLOTS. A calm dashed outline round each slot that can be ordered when the avatar is within NEAR_SLOT tiles (the Build screen's own gold outline takes over when the screen is open,
##  `build_node.gd`); with the Build page open the locked slots are drawn dim with a padlock and the crew they need; a section that has fallen is outlined in red.
##  HITS. A claw on a section (`claw` event) shakes it for a moment and puffs a little dust through `sim.fx` (smoke, shortened; wood chips for the wooden kits). A section that is
##  mended or finished flashes white for a moment.
##
## COST. The cells are made into a list of draw commands only when something about the sections changed (polled four times a second; a hash of their states), sorted by picture so
## the 2D renderer joins them: a built ring is a handful of draw calls (one for each atlas used), nothing is made in a frame. A section that is shaking is drawn by a second node that
## redraws each frame for the quarter second it lasts; everything else is retained. Sources are all soft: no `perimeter`, no base, nothing to draw.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const BuildNode := preload("res://scripts/render/build_node.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const TILE := GD.TILE
## The kit's pictures are 128 px to the tile, the world's tile is 64.
const PX := 0.5
const EVERY := 0.25
## An open slot is outlined when the avatar is this near (tiles from the edge of the slot).
const NEAR_SLOT := 6.0
## How many of the cells of a section that is under 66% show damage.
const WEAR_PCT := 45
const SHAKE_S := 0.26
const SHAKE_PX := 3.4
const FLASH_S := 0.55
const HIT_REACH := 1.7
const HIT_EVERY := 0.12
const MAX_PUFFS := 14
## The lamps of a floodlight: how far they light (tiles), how bright, the colour, and where the light sits relative to the foot of the pole (it falls a little ahead of the head).
const LAMP_R := 10.5
const LAMP_ENERGY := 1.0
const LAMP_COLOR := Color(0.89, 0.92, 1.0)
const LAMP_FROM := 0.08
const LAMP_RAMP := 4.0
const LAMP_AT := Vector2(0.0, -1.3)
## The head of the lamp, from the foot of the pole (tiles): the glow is drawn there.
const HEAD_AT := Vector2(0.0, -3.05)
const GLOW_R := 0.8
const GLOW_ALPHA := 0.5

const OPEN_COL := Color(0.62, 0.87, 0.80)
const LOCK_COL := Color(0.74, 0.78, 0.86)
const BREACH_COL := Color(0.90, 0.36, 0.30)
const GOLD := Color(0.941, 0.761, 0.29)
const WAIT_COL := Color(0.5, 0.65, 0.79)
const PLATE := Color(0.043, 0.078, 0.067)
const PAPER := Color(0.93, 0.9, 0.82)

## The order things are drawn in (low first), then by picture.
const O_RUBBLE := 0
const O_FENCE := 1
const O_GATE := 2
const O_TOWER := 3
const O_PLANKS := 4
const O_GHOST := 5

const FENCE_ITEMS := {"fence": "fort_fence_wood", "fence_strong": "fort_fence_reinforced"}
const SIDES := ["N", "E", "S", "W"]

var sim
var main
var per
var avatar_house := -1
## A number of synthetic sections to draw round the base as well (a stress test of the draw cost: `--slots=stress`); 0 for none. They exist only in the view.
var stress := 0

var _view := Rect2()
var _clock := 0.0
var _scan_t := 0.0
var _sig := 0
var _fx_sig := 0
var _secs: Array = []
var _slots: Array = []
var _posts := {}
var _sides := {}
var _gate_open := false
var _ops: Array = []
var _sec_ops := {}
var _fx := {}
var _last_hit := {}
var _seen := {}
var _atlas_cache := {}
var _tex_cache := {}
var _puffs: Array = []
var _ground: Node2D
var _dust: Node2D
var _dyn: Node2D
var _marks: Node2D
var _glow: Node2D
var _flood := {}
var _lamp_on := 0.0
var _avatar_tile := Vector2i(-99999, -99999)
var _build_open := false
var _hover := ""
## What the last draw put on the screen (a screenshot or a probe reads them).
var drawn_ops := 0
var drawn_textures := 0
## How many runs of one picture the retained draw list has (each is about one draw call).
var runs := 0
var drawn_marks := 0
var rebuilds := 0


func _init() -> void:
	z_index = 5
	_ground = DrawNode.new()
	_ground.name = "Ground"
	_ground.painter = _paint_ground
	add_child(_ground)
	_marks = DrawNode.new()
	_marks.name = "Marks"
	_marks.painter = _paint_marks
	add_child(_marks)
	_dyn = DrawNode.new()
	_dyn.name = "Hit"
	_dyn.painter = _paint_dyn
	add_child(_dyn)
	_dust = DrawNode.new()
	_dust.name = "Dust"
	_dust.z_index = 3
	_dust.painter = _paint_dust
	add_child(_dust)
	var glow_layer := CanvasLayer.new()
	glow_layer.name = "GlowLayer"
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow = DrawNode.new()
	_glow.name = "Glow"
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.material = add
	_glow.painter = _paint_glow
	glow_layer.add_child(_glow)


# ---------------------------------------------------------------- the facade's --

func on_ready(game) -> void:
	var world = game.get("world")
	if world != null and get_parent() == null:
		world.add_child(self)
	bind(game.get("sim"), game)


## `rules` is the sim, `game` main.gd (or a stand-in: it is asked for entities, lighting, build_open, build_hover, build_view; all soft).
func bind(rules, game = null) -> void:
	sim = rules
	main = game
	per = sim.get("perimeter") if sim != null else null
	_sig = 0
	_forget()


func on_sync_views(view: Rect2) -> void:
	_view = view


func on_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"claw":
			_on_claw(e)
		"slot_built", "slot_lost", "slot_ordered", "gate_base", "crash", "built", "demolished", "site", "cancelled":
			_scan_t = 0.0


func on_frame(dt: float) -> void:
	if per == null:
		return
	_clock += dt
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = EVERY
		_scan()
	_tick_fx(dt)
	_tick_lamps()
	var me = _avatar()
	if me != null:
		var t := Vector2i(floori(me.x), floori(me.y))
		if t != _avatar_tile:
			_avatar_tile = t
			_marks.queue_redraw()
	var open := _screen_open()
	var hover := _hover_plot()
	if open != _build_open or hover != _hover:
		_build_open = open
		_hover = hover
		_marks.queue_redraw()


func _exit_tree() -> void:
	_forget()


# ------------------------------------------------------------------------ data --

func _avatar():
	if sim == null or sim.get("avatar") == null:
		return null
	return sim.avatar.player()


func _screen_open() -> bool:
	return main != null and bool(main.get("build_open"))


func _hover_plot() -> String:
	var h = main.get("build_hover") if main != null else null
	return String(h.get("plot", "")) if h is Dictionary else ""


## Everything the part holds is dropped (a new base, a load, the part is freed).
func _forget() -> void:
	_ops = []
	_sec_ops = {}
	_secs = []
	_slots = []
	_fx = {}
	_seen = {}
	_puffs = []
	for id in _flood.keys():
		_drop_flood(id)
	_flood = {}
	if _ground != null:
		_ground.queue_redraw()
		_marks.queue_redraw()
		_dyn.queue_redraw()
		_glow.queue_redraw()


## Reads the module (four times a second) and makes the draw list again when what stands, or how it stands, has changed.
func _scan() -> void:
	if per == null or per.layout.is_empty():
		if not _secs.is_empty() or not _slots.is_empty():
			_forget()
		return
	_secs = per.sections()
	if stress > 0:
		_secs.append_array(_stress_sections(stress))
	_slots = per.slots()
	_gate_open = per.gate_open()
	_sides = {}
	for ls in per.layout.get("slots", []):
		_sides[String(ls.id)] = String(ls.get("side", "S"))
	_posts = {}
	for po in per.layout.get("posts", []):
		if String(po.get("slot", "")) != "":
			_posts[String(po.slot)] = Vector2(float(po.pos[0]), float(po.pos[1]))
	var sig := [_gate_open]
	for s in _secs:
		sig.append([int(s.id), int(s.state), String(s.kit)])
		_note_state(s)
	for sl in _slots:
		var share := 0.0
		if sl.state == "building" or sl.state == "ordered":
			share = sim.build.progress_of(String(sl.plot))
		sig.append([String(sl.id), String(sl.state), String(sl.kit), int(share * 24.0)])
	var h := hash(sig)
	if h != _sig or hash(_fx.keys()) != _fx_sig:
		_sig = h
		_rebuild()
	_marks.queue_redraw()


## `n` made-up sections of four tiles in rings round the base (all four states, both kits, a gate now and then), for counting draw calls.
func _stress_sections(n: int) -> Array:
	var out: Array = []
	var lot := Rect2i(per.layout.get("plot", Rect2i(0, 0, 14, 13)))
	var ring := 0
	while out.size() < n and ring < 6:
		var pad := 6 + ring * 3
		var x0 := lot.position.x - pad
		var y0 := lot.position.y - pad
		var x1 := lot.end.x + pad - 1
		var y1 := lot.end.y + pad - 1
		var rects: Array = []
		for side in ["N", "S"]:
			var x := x0
			while x <= x1:
				var w := mini(4, x1 - x + 1)
				rects.append([Rect2i(x, y0 if side == "N" else y1, w, 1), side])
				x += w
		for side in ["W", "E"]:
			var y := y0 + 1
			while y <= y1 - 1:
				var h := mini(4, y1 - y)
				rects.append([Rect2i(x0 if side == "W" else x1, y, 1, h), side])
				y += h
		for r in rects:
			if out.size() >= n:
				break
			var i := out.size()
			var state: int = [0, 0, 1, 2, 0, 1, 0, 2][i % 8]
			if i % 17 == 16:
				state = 3
			var gate: bool = i % 13 == 12 and state != 3
			out.append({"id": 1000 + i, "slot": "stress_%d" % i, "kind": "gate" if gate else "fence", "kit": "gate" if gate else ("fence_strong" if i % 3 == 0 else "fence"),
				"rect": r[0], "side": r[1], "hp": 100.0, "max_hp": 100.0, "state": state})
		ring += 1
	return out


## A section whose state got better was mended, a new one was finished: it flashes. (Sections seen for the first time at a load do not.)
func _note_state(s: Dictionary) -> void:
	var id := int(s.id)
	var now := int(s.state)
	if _seen.has(id):
		var was: int = _seen[id]
		if now < was and not _fx.has(id):
			_fx[id] = {"kind": "flash", "t": 0.0, "dur": FLASH_S}
			_puff(_center_of(s.rect), 3, String(s.kit) != "fence_strong")
	elif not _seen.is_empty() and now == 0 and _clock > 1.0:
		_fx[id] = {"kind": "flash", "t": 0.0, "dur": FLASH_S}
	_seen[id] = now


# --------------------------------------------------------------------- the ops --

static func _key(t: Vector2i) -> int:
	return t.y * 100000 + t.x


static func _tiles_of(r: Rect2i) -> Array:
	var out: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


static func _scatter(t: Vector2i, salt: int = 0) -> int:
	return ((t.x * 73856093) ^ (t.y * 19349663) ^ (salt * 83492791)) & 0x7fffffff


static func _center_of(r) -> Vector2:
	var rr := Rect2(Vector2(r.position), Vector2(r.size))
	return rr.get_center()


## The side of the lot a slot is on (the layout's).
func _side_of(sl: Dictionary) -> String:
	return String(_sides.get(String(sl.id), "S"))


func _orient(side: String) -> String:
	return "h" if side == "N" or side == "S" else "v"


func _atlas(id: String) -> Dictionary:
	if not _atlas_cache.has(id):
		var d := TownArt.atlas(id)
		d["tex"] = TownArt.texture(d) if not bool(d.placeholder) else null
		_atlas_cache[id] = d
	return _atlas_cache[id]


func _tex(d: Dictionary) -> Texture2D:
	var file := String(d.get("file", ""))
	if file == "":
		return null
	if not _tex_cache.has(file):
		_tex_cache[file] = TownArt.texture(d)
	return _tex_cache[file]


## One draw command: [order, picture (or null: a flat colour), where (px), which part of the picture (px), tint, the picture's file (the sort key)].
func _op(order: int, tex, dst: Rect2, src: Rect2, tint: Color, file: String = "") -> Array:
	return [order, tex, dst, src, tint, file]


## Makes every draw command again from `_secs` and `_slots`. Sections that are shaking or flashing are left out of the retained list (the second node draws them).
func _rebuild() -> void:
	rebuilds += 1
	_ops = []
	_sec_ops = {}
	_fx_sig = hash(_fx.keys())
	var occ := {}
	for s in _secs:
		if String(s.kind) == "door" or int(s.state) == 3:
			continue
		for t in _tiles_of(Rect2i(s.rect)):
			occ[_key(t)] = true
	var planked := _planked_doors()
	for s in _secs:
		var id := int(s.id)
		var ops: Array = []
		match String(s.kind):
			"door":
				ops = _door_ops(s, planked.get(String(s.slot), ""))
			"gate":
				ops = _gate_ops(s)
			_:
				ops = _fence_ops(s, occ)
		_sec_ops[id] = ops
		if not _fx.has(id):
			_ops.append_array(ops)
	for sl in _slots:
		match String(sl.state):
			"built":
				if String(sl.kind) == "tower":
					_ops.append_array(_tower_ops(sl, 1.0, 0))
			"ordered", "building":
				_ops.append_array(_ghost_ops(sl, occ))
	_ops.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and String(a[5]) < String(b[5])))
	runs = 0
	var last = null
	for op in _ops:
		if op[1] != last:
			runs += 1
			last = op[1]
	if stress > 0:
		print("perimeter_view: %d draw commands for %d sections in %d runs of one picture (the 2D renderer joins each run into one draw call)" % [_ops.size(), _secs.size(), runs])
	_sync_flood()
	_ground.queue_redraw()
	_dyn.queue_redraw()
	_marks.queue_redraw()


## Which doors carry the plank kit: door id ("door_front") -> kit id.
func _planked_doors() -> Dictionary:
	var out := {}
	for sl in _slots:
		if String(sl.kind) != "door" or String(sl.state) != "built" or String(sl.kit) == "":
			continue
		for s in _secs:
			if String(s.kind) == "door" and String(sl.id).contains(String(s.slot).trim_prefix("door_")):
				out[String(s.slot)] = String(sl.kit)
	return out


func _fence_ops(s: Dictionary, occ: Dictionary) -> Array:
	var out: Array = []
	var rect := Rect2i(s.rect)
	var state := int(s.state)
	var kit := String(s.kit) if FENCE_ITEMS.has(String(s.kit)) else "fence"
	var along_x := String(s.side) == "N" or String(s.side) == "S"
	if state == 3:
		for t in _tiles_of(rect):
			out.append_array(_rubble_ops(t, along_x))
		return out
	for t in _tiles_of(rect):
		var look := "built"
		if state >= 2 or (state == 1 and _scatter(t) % 100 < WEAR_PCT):
			look = "damaged"
		out.append(_fence_cell(t, FENCE_ITEMS[kit] + "_" + look, _mask(t, occ), Color.WHITE, O_FENCE, kit, along_x))
	return out


## The bits of a fence that stands: the mask of the sides that join another standing cell.
func _mask(t: Vector2i, occ: Dictionary) -> int:
	var m := 0
	if occ.has(_key(t + Vector2i(0, -1))):
		m |= 1
	if occ.has(_key(t + Vector2i(1, 0))):
		m |= 2
	if occ.has(_key(t + Vector2i(0, 1))):
		m |= 4
	if occ.has(_key(t + Vector2i(-1, 0))):
		m |= 8
	return m


func _fence_cell(t: Vector2i, item: String, mask: int, tint: Color, order: int, kit: String, along_x: bool) -> Array:
	var dst := Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))
	var atl := _atlas(item)
	if atl.tex == null:
		var c: Color = TownArt.fence(kit, "built").color
		var line := Rect2(dst.position + (Vector2(0.0, 0.34 * TILE) if along_x else Vector2(0.34 * TILE, 0.0)), Vector2(TILE, 0.32 * TILE) if along_x else Vector2(0.32 * TILE, TILE))
		return _op(order, null, line, Rect2(), Color(c, tint.a))
	return _op(order, atl.tex, dst, TownArt.atlas_rect(atl, mask), tint, String(atl.file))


## What lies where a fence has fallen: a few planks on the ground (the kit's rubble cell when it has one).
func _rubble_ops(t: Vector2i, along_x: bool) -> Array:
	var out: Array = []
	var atl := _atlas("fence_rubble")
	var dst := Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))
	if atl.tex != null:
		var col := _scatter(t, 5) % int(atl.cols)
		var src := Rect2(float(col) * atl.cell.x, (0.0 if along_x else atl.cell.y), atl.cell.x, atl.cell.y)
		out.append(_op(O_RUBBLE, atl.tex, dst, src, Color.WHITE, String(atl.file)))
		return out
	var wood := Color(0.30, 0.22, 0.16)
	for i in 3:
		var r := _scatter(t, 7 + i)
		var off := float(r % 40) / 100.0 + 0.1
		var len := (0.28 + float((r >> 8) % 30) / 100.0) * TILE
		var thick := 0.10 * TILE
		var at := dst.position + Vector2(float((r >> 4) % 60) / 100.0, off) * TILE if along_x else dst.position + Vector2(off, float((r >> 4) % 60) / 100.0) * TILE
		out.append(_op(O_RUBBLE, null, Rect2(at, Vector2(len, thick) if along_x else Vector2(thick, len)), Rect2(), wood))
	return out


func _gate_ops(s: Dictionary) -> Array:
	var out: Array = []
	var rect := Rect2i(s.rect)
	var state := int(s.state)
	if state == 3:
		for t in _tiles_of(rect):
			out.append_array(_rubble_ops(t, _orient(String(s.side)) == "h"))
		return out
	out.append(_gate_piece(rect, String(s.side), _gate_open, 1 if state >= 2 else 0, Color.WHITE, O_GATE))
	return out


func _gate_piece(rect: Rect2i, side: String, open: bool, variant: int, tint: Color, order: int) -> Array:
	var orient := _orient(side)
	var horizontal := orient == "h"
	var len := float(rect.size.x if horizontal else rect.size.y)
	var id := "fort_gate_wide" if TownArt.has_item("fort_gate_wide") else "fort_gate"
	var d := TownArt.piece(id, orient, "open" if open else "closed", variant, Vector2(len, 1.0) if horizontal else Vector2(1.0, len))
	var tex := _tex(d)
	if tex == null:
		var flat := Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE).grow(-0.18 * TILE)
		return _op(order, null, flat, Rect2(), Color(d.color, tint.a))
	var fp: Vector2 = d.size
	var dst_size: Vector2 = Rect2(d.rect).size * PX
	if horizontal and absf(fp.x - len) > 0.01:
		dst_size.x *= len / fp.x
	elif not horizontal and absf(fp.y - len) > 0.01:
		dst_size.y *= len / fp.y
	var dst := Rect2((Vector2(rect.position) - Vector2(d.anchor)) * TILE, dst_size)
	# a gate in a north side is the picture turned over (its outside is the north): a negative height flips it about the middle of its row
	if horizontal and side == "N":
		dst = Rect2(Vector2(dst.position.x, (float(rect.position.y) + 1.0 + Vector2(d.anchor).y) * TILE), Vector2(dst.size.x, -dst.size.y))
	return _op(order, tex, dst, d.rect, tint, String(d.file))


func _door_ops(s: Dictionary, kit: String) -> Array:
	var out: Array = []
	var rect := Rect2i(s.rect)
	var state := int(s.state)
	var orient := _orient(String(s.side))
	if state == 3:
		for t in _tiles_of(rect):
			out.append_array(_rubble_ops(t, orient == "h"))
		return out
	for t in _tiles_of(rect):
		out.append(_plank_cell(t, orient, 1 if state >= 2 else 0, "barricade_door", Color.WHITE, O_PLANKS))
		if kit != "":
			var extra := "door_reinforce" if TownArt.has_item("door_reinforce") else "barricade_window"
			out.append(_plank_cell(t, orient, 1 if state >= 2 else 0, extra, Color.WHITE, O_PLANKS + 0))
	return out


func _plank_cell(t: Vector2i, orient: String, variant: int, item: String, tint: Color, order: int) -> Array:
	var d := TownArt.piece(item, orient, "", variant)
	var tex := _tex(d)
	var dst := Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))
	if tex == null:
		return _op(order, null, dst.grow(-0.12 * TILE), Rect2(), Color(0.45, 0.33, 0.22, tint.a))
	return _op(order, tex, dst, d.rect, tint, String(d.file))


## The deck of a tower over its tile and the tile of the shooter's post (the layout's post of that slot).
func _tower_rect(sl: Dictionary) -> Rect2i:
	var t := Rect2i(sl.rect).position
	var lo := t
	var hi := t
	var post: Vector2 = _posts.get(String(sl.id), Vector2(-1.0, -1.0))
	if post.x >= 0.0:
		var p := Vector2i(floori(post.x), floori(post.y))
		lo = Vector2i(mini(t.x, p.x), mini(t.y, p.y))
		hi = Vector2i(maxi(t.x, p.x), maxi(t.y, p.y))
	if hi.y == lo.y:    # (no post of its own: the deck takes the tile in front of it)
		hi.y += 1
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _tower_ops(sl: Dictionary, alpha: float, variant: int) -> Array:
	var r := _tower_rect(sl)
	var id := "fort_tower_post" if TownArt.has_item("fort_tower_post") else "fort_tower"
	var d := TownArt.piece(id, "", "", variant, Vector2(r.size))
	var tex := _tex(d)
	if tex == null:
		return [_op(O_TOWER, null, Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE).grow(-0.06 * TILE), Rect2(), Color(d.color, alpha))]
	var fp: Vector2 = d.size
	var scale := Vector2(float(r.size.x) / fp.x, float(r.size.y) / fp.y)
	var dst := Rect2((Vector2(r.position) - Vector2(d.anchor) * scale) * TILE, Rect2(d.rect).size * PX * scale)
	return [_op(O_TOWER, tex, dst, d.rect, Color(1, 1, 1, alpha), String(d.file))]


## What a slot that is ordered or going up shows: its ghost, fuller as the work is done.
func _ghost_ops(sl: Dictionary, occ: Dictionary) -> Array:
	var out: Array = []
	var share: float = sim.build.progress_of(String(sl.plot))
	var rect := Rect2i(sl.rect)
	var ghost := Color(0.86, 0.95, 1.0, 0.40)
	match String(sl.kind):
		"fence":
			var kit := String(sl.kit) if FENCE_ITEMS.has(String(sl.kit)) else "fence"
			var tiles := _tiles_of(rect)
			var own := occ.duplicate()
			for t in tiles:
				own[_key(t)] = true
			var done := share * float(tiles.size())
			var along_x := _side_of(sl) == "N" or _side_of(sl) == "S"
			for i in tiles.size():
				var t: Vector2i = tiles[i]
				var tint := ghost
				if float(i + 1) <= done:
					tint = Color(1, 1, 1, 0.96)
				elif float(i) < done:
					tint = ghost.lerp(Color(1, 1, 1, 0.96), done - float(i))
				out.append(_fence_cell(t, FENCE_ITEMS[kit] + "_built", _mask(t, own), tint, O_GHOST, kit, along_x))
		"gate":
			out.append(_gate_piece(rect, _side_of(sl), false, 0, ghost.lerp(Color(1, 1, 1, 0.9), share), O_GHOST))
		"tower":
			var tw := _tower_ops(sl, 0.0, 0)
			for o in tw:
				o[4] = ghost.lerp(Color(1, 1, 1, 0.9), share)
				o[0] = O_GHOST
			out.append_array(tw)
		"floodlight":
			var d := TownArt.piece("floodlight", "", "", 0)
			var tex := _tex(d)
			if tex != null:
				var tint := ghost.lerp(Color(1, 1, 1, 0.9), share)
				out.append(_op(O_GHOST, tex, Rect2((Vector2(rect.position) - Vector2(d.anchor)) * TILE, Rect2(d.rect).size * PX), d.rect, tint, String(d.file)))
		"door":
			var orient := _orient(_side_of(sl))
			var kit_item := "door_reinforce" if TownArt.has_item("door_reinforce") else "barricade_window"
			var tint := ghost.lerp(Color(1, 1, 1, 0.9), share)
			for d in _door_tiles(sl):
				out.append(_plank_cell(d, orient, 0, kit_item, tint, O_GHOST))
	return out


## The tiles of the door a door slot is on (the section the module made for it).
func _door_tiles(sl: Dictionary) -> Array:
	for s in _secs:
		if String(s.kind) == "door" and String(sl.id).contains(String(s.slot).trim_prefix("door_")):
			return _tiles_of(Rect2i(s.rect))
	return _tiles_of(Rect2i(sl.rect))


# ---------------------------------------------------------------- the floodlights --

## The poles: a sprite among the people for each floodlight that stands (sorted by its foot), and a light on its head.
func _sync_flood() -> void:
	var want := {}
	for sl in _slots:
		if String(sl.kind) == "floodlight" and String(sl.state) == "built":
			want[String(sl.id)] = sl
	for id in _flood.keys():
		if not want.has(id):
			_drop_flood(id)
	for id in want:
		if not _flood.has(id):
			_make_flood(want[id])


func _make_flood(sl: Dictionary) -> void:
	var foot := Vector2(Rect2i(sl.rect).position)
	var entry := {"sprite": null, "light": null, "foot": foot + Vector2(0.5, 0.5)}
	var d := TownArt.piece("floodlight", "", "", 0)
	var tex := _tex(d)
	var stand_in = main.get("entities") if main != null else null
	if tex != null and stand_in != null:
		var s := Sprite2D.new()
		s.name = "Floodlight_" + String(sl.id)
		s.texture = tex
		s.centered = false
		s.region_enabled = true
		s.region_rect = d.rect
		s.scale = Vector2(PX, PX)
		s.position = (foot + Vector2(0.5, 0.82)) * TILE
		s.offset = ((foot - Vector2(d.anchor)) * TILE - s.position) / PX
		stand_in.add_child(s)
		entry.sprite = s
	var light := PointLight2D.new()
	light.name = "FloodLight_" + String(sl.id)
	light.texture = BuildNode.light_texture(LAMP_R)
	light.texture_scale = LAMP_R * 2.0 * TILE / 128.0
	light.position = (entry.foot + LAMP_AT) * TILE
	light.color = LAMP_COLOR
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.energy = 0.0
	light.visible = false
	add_child(light)
	entry.light = light
	_flood[String(sl.id)] = entry


func _drop_flood(id) -> void:
	var entry: Dictionary = _flood.get(id, {})
	for k in ["sprite", "light"]:
		var n = entry.get(k)
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_flood.erase(id)


## How strongly the lamps burn: from the dark of the sky, not the power (the base brings its own generator, as the school's floodlights do).
func lamp_level() -> float:
	var lighting = main.get("lighting") if main != null else null
	if lighting == null or not lighting.visible:
		return 0.0
	return clampf((float(lighting.dark) - LAMP_FROM) * LAMP_RAMP, 0.0, 1.0)


func _tick_lamps() -> void:
	if _flood.is_empty() and _lamp_on == 0.0:
		return
	var level := lamp_level()
	var lighting = main.get("lighting") if main != null else null
	var fog: float = float(lighting.fog) if lighting != null else 0.0
	var energy_k := lerpf(1.0, Lighting.FOG_LIGHT_ENERGY, fog)
	var reach_k := lerpf(1.0, Lighting.FOG_LIGHT_REACH, fog)
	for id in _flood:
		var light: PointLight2D = _flood[id].light
		var e := minf(1.0, LAMP_ENERGY * level) * energy_k
		light.energy = e
		light.texture_scale = LAMP_R * 2.0 * TILE / 128.0 * reach_k
		light.visible = e > 0.01
	if absf(level - _lamp_on) > 0.01:
		_lamp_on = level
		_glow.queue_redraw()


func _paint_glow(ci) -> void:
	if _lamp_on <= 0.02:
		return
	var lighting = main.get("lighting") if main != null else null
	var fog: float = float(lighting.fog) if lighting != null else 0.0
	var a := GLOW_ALPHA * _lamp_on * lerpf(1.0, Lighting.FOG_LIGHT_ENERGY, fog)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for id in _flood:
		var at: Vector2 = _flood[id].foot + HEAD_AT
		ci.draw_texture_rect(BuildNode.radial_texture(), Rect2(at.x - GLOW_R, at.y - GLOW_R, GLOW_R * 2.0, GLOW_R * 2.0), false, Color(1.0, 0.95, 0.85, a))


# ------------------------------------------------------------------------ hits --

func _on_claw(e: Dictionary) -> void:
	if _secs.is_empty():
		return
	var at := Vector2(float(e.x), float(e.y))
	var best: Dictionary = {}
	var best_d := HIT_REACH
	for s in _secs:
		if int(s.state) == 3:
			continue
		var d := _gap(Rect2(Vector2(Rect2i(s.rect).position), Vector2(Rect2i(s.rect).size)), at)
		if d < best_d:
			best_d = d
			best = s
	if best.is_empty():
		return
	var id := int(best.id)
	if _clock - float(_last_hit.get(id, -9.0)) < HIT_EVERY:
		return
	_last_hit[id] = _clock
	if not _fx.has(id):
		_fx[id] = {"kind": "shake", "t": 0.0, "dur": SHAKE_S}
		_scan_t = 0.0
		_rebuild()
	elif _fx[id].kind == "shake":
		_fx[id].t = 0.0
	var rr := Rect2(Vector2(Rect2i(best.rect).position), Vector2(Rect2i(best.rect).size))
	var edge := Vector2(clampf(at.x, rr.position.x, rr.end.x), clampf(at.y, rr.position.y, rr.end.y))
	_puff(edge, 1, String(best.kit) != "fence_strong")


static func _gap(r: Rect2, p: Vector2) -> float:
	var d := Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0))
	return d.length()


## A little dust (a few soft puffs of this node's own, over the people) and, for the wooden kits, wood chips through the fx module.
func _puff(at: Vector2, n: int, wood: bool) -> void:
	for i in n:
		if _puffs.size() >= MAX_PUFFS:
			_puffs.pop_front()
		_puffs.append([at + Vector2(randf() - 0.5, randf() - 0.5) * 0.45, 0.0, 0.45 + randf() * 0.3, 0.10 + randf() * 0.07])
	_dust.queue_redraw()
	var f = sim.get("fx") if sim != null else null
	if f != null and wood and randf() < 0.6:
		f.hit_material(at.x, at.y, "wood")


func _tick_fx(dt: float) -> void:
	if not _puffs.is_empty():
		var kept: Array = []
		for p in _puffs:
			p[1] += dt
			if p[1] < p[2]:
				kept.append(p)
		_puffs = kept
		_dust.queue_redraw()
	if _fx.is_empty():
		return
	var done: Array = []
	for id in _fx:
		_fx[id].t += dt
		if _fx[id].t >= _fx[id].dur:
			done.append(id)
	for id in done:
		_fx.erase(id)
	_dyn.queue_redraw()
	if not done.is_empty():
		_rebuild()


# ---------------------------------------------------------------------- drawing --

func _paint_ground(ci) -> void:
	drawn_ops = 0
	drawn_textures = 0
	var last = null
	for op in _ops:
		var tex = op[1]
		if tex == null:
			ci.draw_rect(op[2], op[4])
		else:
			ci.draw_texture_rect_region(tex, op[2], op[3], op[4])
			if tex != last:
				drawn_textures += 1
				last = tex
		drawn_ops += 1


## The sections that are shaking or flashing, drawn on their own: the shake moves them a few pixels, the flash lays white over them.
func _paint_dyn(ci) -> void:
	for id in _fx:
		var f: Dictionary = _fx[id]
		var k: float = 1.0 - float(f.t) / float(f.dur)
		var off := Vector2.ZERO
		var flash := 0.0
		if f.kind == "shake":
			off = Vector2(sin(_clock * 83.0), sin(_clock * 61.0 + 1.3) * 0.55) * SHAKE_PX * k
		else:
			flash = 0.55 * k
		for op in _sec_ops.get(id, []):
			var dst: Rect2 = op[2]
			dst.position += off
			if op[1] == null:
				ci.draw_rect(dst, op[4])
			else:
				ci.draw_texture_rect_region(op[1], dst, op[3], op[4])
		if flash > 0.01:
			for op in _sec_ops.get(id, []):
				if op[1] != null:
					ci.draw_texture_rect_region(op[1], op[2], op[3], Color(1, 1, 1, flash))


## The dust of the hits: soft warm puffs that swell and thin out as they rise a little.
func _paint_dust(ci) -> void:
	if _puffs.is_empty():
		return
	var tex := BuildNode.radial_texture()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for p in _puffs:
		var k: float = float(p[1]) / float(p[2])
		var r: float = float(p[3]) + 0.30 * k
		var a: float = 0.55 * (1.0 - k) * minf(1.0, float(p[1]) * 12.0)
		var at: Vector2 = p[0] + Vector2(0.0, -0.3 * k)
		ci.draw_texture_rect(tex, Rect2(at.x - r, at.y - r, r * 2.0, r * 2.0), false, Color(0.84, 0.77, 0.64, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _screen_scale() -> float:
	if not is_inside_tree():
		return 0.4
	return maxf(get_viewport().get_canvas_transform().get_scale().x, 0.01)


## The marks of the slots: the calm outlines of the open ones near the avatar, the locked ones' padlocks while the Build page is open, the red outline of a breach, a progress ring on a site.
func _paint_marks(ci) -> void:
	drawn_marks = 0
	if per == null or _slots.is_empty():
		return
	var k := 1.0 / _screen_scale()
	var me = _avatar()
	var at := Vector2(me.x, me.y) if me != null else Vector2(-9999.0, -9999.0)
	var bv = main.get("build_view") if main != null else null
	var pulse := 0.5 + 0.5 * sin(_clock * 3.0)
	for sl in _slots:
		var rect := Rect2(Vector2(Rect2i(sl.rect).position), Vector2(Rect2i(sl.rect).size))
		if _view.has_area() and not _view.grow(3.0).intersects(rect):
			continue
		match String(sl.state):
			"open":
				var near := _gap(rect, at) <= NEAR_SLOT
				var lit := false
				if bv != null:
					var pl: Dictionary = sim.build.plot(String(sl.plot))
					lit = not pl.is_empty() and float(bv.outline_alpha(pl)) > 0.01
				if near and not lit and not _build_open:
					_outline(ci, rect, Color(OPEN_COL, 0.66), 0.05, k, 2.0)
					drawn_marks += 1
			"locked":
				if _build_open:
					var hot: bool = String(sl.plot) == _hover
					_outline(ci, rect, Color(LOCK_COL, 0.62 if hot else 0.34), 0.0, k, 1.6)
					_padlock(ci, rect, int(sl.unlock.crew), 0.9 if hot else 0.62, k)
					drawn_marks += 1
			"broken":
				_outline(ci, rect, Color(BREACH_COL, 0.55 + 0.4 * pulse), 0.07, k, 2.4)
				drawn_marks += 1
			"ordered", "building":
				_ring(ci, rect, sim.build.progress_of(String(sl.plot)), String(sl.state) == "ordered", k)
				drawn_marks += 1


## A dashed rectangle in tiles (screen-constant width), with a faint wash.
func _outline(ci, r: Rect2, col: Color, fill: float, k: float, width: float) -> void:
	var box := Rect2(r.position * TILE, r.size * TILE).grow(0.06 * TILE)
	if fill > 0.0:
		ci.draw_rect(box, Color(col, fill))
	var a := box.position
	var b := Vector2(box.end.x, box.position.y)
	var c := box.end
	var d := Vector2(box.position.x, box.end.y)
	var dash := 0.30 * TILE
	for edge in [[a, b], [b, c], [c, d], [d, a]]:
		ci.draw_dashed_line(edge[0], edge[1], col, width * k, dash, true)


## A padlock with the crew a slot needs, at the middle of a slot.
func _padlock(ci, r: Rect2, crew: int, alpha: float, k: float) -> void:
	var c := (r.position + r.size * 0.5) * TILE
	var px := clampf(0.26 * TILE / k, 8.0, 11.0) * k
	ci.draw_circle(c, px * 1.25, Color(PLATE, 0.78 * alpha))
	ci.draw_arc(c, px * 1.25, 0.0, TAU, 20, Color(LOCK_COL, alpha * 0.8), 1.4 * k, true)
	var body := Rect2(c + Vector2(-0.55, -0.12) * px, Vector2(1.1, 0.85) * px)
	ci.draw_rect(body, Color(PAPER, alpha))
	ci.draw_arc(c + Vector2(0.0, -0.12) * px, 0.38 * px, PI, TAU, 10, Color(PAPER, alpha), 1.6 * k, true)
	ci.draw_line(body.position + Vector2(0.0, 0.0), body.position + Vector2(body.size.x, 0.0), Color(PLATE, alpha * 0.5), 1.0 * k)
	var font: Font = Fonts.cond(700)
	var text := str(crew)
	var size := int(clampf(11.0, 9.0, 13.0))
	ci.draw_set_transform(c + Vector2(px * 1.5, px * 0.55), 0.0, Vector2(k, k))
	ci.draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(PLATE, alpha))
	ci.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(PAPER, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The progress of a site as a ring at its middle (gold by day, cool blue while the work waits for the day).
func _ring(ci, r: Rect2, share: float, waiting_order: bool, k: float) -> void:
	var c := (r.position + r.size * 0.5) * TILE
	var rad := clampf(0.26 * TILE / k, 8.0, 13.0) * k
	var by_day := _day()
	var col := GOLD if by_day else WAIT_COL
	ci.draw_circle(c, rad + 1.6 * k, Color(0, 0, 0, 0.35))
	ci.draw_circle(c, rad, Color(PLATE, 0.8))
	if share > 0.0:
		ci.draw_arc(c, rad * 0.72, -PI / 2.0, -PI / 2.0 + TAU * share, 28, col, 3.2 * k, true)
	else:
		ci.draw_arc(c, rad * 0.72, 0.0, TAU, 20, Color(col, 0.35), 1.6 * k, true)
	if waiting_order:
		ci.draw_circle(c, 1.6 * k, Color(col, 0.8))


func _day() -> bool:
	if sim == null:
		return true
	var phase := String(sim.phase)
	return not (phase == "night" or phase == "dawn" or (phase == "dusk" and bool(sim.bell_rung)))
